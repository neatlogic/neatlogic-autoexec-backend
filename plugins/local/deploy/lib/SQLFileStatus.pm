#!/usr/bin/perl
use strict;

package SQLFileStatus;

use FindBin;
use POSIX qw(strftime);
use Fcntl qw(:flock O_RDWR O_CREAT O_SYNC);
use IO::File;
use File::Path;
use Cwd;
use Digest::MD5;
use File::Basename;
use Getopt::Long;
use JSON;

use ServerAdapter;
use DBInfo;
use DeployUtils;
use Data::Dumper;

sub new {
    my ( $type, $sqlFile, %args ) = @_;

    my $self = {
        sqlFile      => $sqlFile,
        jobId        => $args{jobId},
        deployEnv    => $args{deployEnv},
        dbInfo       => $args{dbInfo},
        sqlFileDir   => $args{sqlFileDir},
        sqlStatusDir => $args{sqlStatusDir},
        status       => {}
    };

    my $sqlSubDir  = dirname($sqlFile);
    my $statusDir  = $self->{sqlStatusDir};
    my $sqlFileDir = $self->{sqlFileDir};

    if ( not -e $statusDir ) {
        if ( not mkpath($statusDir) ) {
            die("ERROR: Create directory $statusDir failed $!\n");
        }
    }
    if ( $sqlSubDir ne '.' and not -e "$statusDir/$sqlSubDir" ) {
        if ( not mkpath("$statusDir/$sqlSubDir") ) {
            die("ERROR: Create directory $statusDir/$sqlSubDir failed $!\n");
        }
    }

    $self->{sqlPath}       = "$sqlFileDir/$sqlFile";
    $self->{statusPath}    = "$statusDir/$sqlFile.txt";
    $self->{serverAdapter} = ServerAdapter->new();

    bless( $self, $type );

    my $newSqlFile = 1;
    if ( -e $self->{statusPath} ) {
        $newSqlFile = 0;
    }

    my $fh;
    sysopen( $fh, $self->{statusPath}, O_RDWR | O_CREAT | O_SYNC );
    if ( not defined($fh) ) {
        die("ERROR: Create status file $self->{statusPath} failed $!\n");
    }

    $fh->autoflush(1);
    $self->{statusFH} = $fh;

    if ( $newSqlFile == 0 ) {
        $self->_loadStatus();
    }
    else {
        $self->{status} = { "status" => "pending", "isModified" => 0, "warnCount" => 0, "md5" => '', "interact" => undef };
        $self->_saveStatus();
    }

    END {
        if ( defined($fh) ) {
            close($fh);
        }
    }

    return $self;
}

sub getFileContent {
    my ( $self, $filePath ) = @_;
    my $content;

    if ( -f $filePath ) {
        my $size = -s $filePath;
        my $fh   = new IO::File("<$filePath");

        if ( defined($fh) ) {
            $fh->read( $content, $size );
            $fh->close();
        }
        else {
            print("WARN: Open file $filePath failed $!\n");
        }
    }

    return $content;
}

sub _lockStatus {
    my ( $self, $lockShare ) = @_;

    my $lockMod = LOCK_EX;
    if ( $lockShare eq 1 ) {
        $lockMod = LOCK_SH;
    }

    my $fh = $self->{statusFH};
    flock( $fh, $lockMod );
}

sub _unlockStatus {
    my ($self) = @_;

    my $fh = $self->{statusFH};
    flock( $fh, LOCK_UN );
}

#md5:xxxxx
#status:xxxxxx
#warnCount:xxxxxx
#interact:xxxxxxxxx
sub _loadStatus {
    my ($self) = @_;

    $self->_lockStatus(1);
    my $jsonStr = $self->getFileContent( $self->{statusPath} );

    my $status = {};
    if ( defined($jsonStr) and $jsonStr ne '' ) {
        $status = from_json($jsonStr);
        $self->{status} = $status;
    }

    $self->_unlockStatus(1);
}

sub _saveStatus {
    my ($self) = @_;

    $self->_lockStatus(0);
    my $jsonStr = to_json( $self->{status} );
    my $fh      = $self->{statusFH};

    $fh->seek( 0, 0 );
    truncate( $fh, 0 );
    syswrite( $fh, $jsonStr );

    $self->_unlockStatus(0);
}

sub _setStatus {
    my ( $self, %args ) = @_;

    my $preStatus = $self->{status}->{status};

    foreach my $key ( keys(%args) ) {
        $self->{status}->{$key} = $args{$key};
    }
    $self->_saveStatus();

    return $preStatus;
}

sub updateStatus {
    my ( $self, %args ) = @_;

    my $preStatus = $self->{status}->{status};

    foreach my $key ( keys(%args) ) {
        $self->{status}->{$key} = $args{$key};
    }
    $self->_saveStatus();

    my $newStatus = $args{status};
    if ( defined( $newStatus and $preStatus ne $newStatus ) ) {

        #如果sql状态发生了切变，则调用服务端接口更新sql状态
        my $serverAdapter = $self->{serverAdapter};
        my $dbInfo        = $self->{dbInfo};

        my $nodeInfo = $dbInfo->{node};
        my $sqlInfo  = {
            jobId          => $self->{jobId},
            resourceId     => $nodeInfo->{resourceId},
            nodeName       => $nodeInfo->{nodeName},
            host           => $nodeInfo->{host},
            port           => $nodeInfo->{port},
            accessEndpoint => $nodeInfo->{accessEndpoint},
            sqlFile        => $self->{sqlFile},
            status         => $newStatus,
            md5            => $self->{status}->{md5},
            interact       => $self->{status}->{interact}
        };

        $serverAdapter->pushSqlStatus( $self->{jobId}, $sqlInfo, $self->{deployEnv} );
    }
    return $preStatus;
}

sub getStatusValue {
    my ( $self, $key ) = @_;

    return $self->{status}->{$key};
}

sub loadAndGetStatusValue {
    my ( $self, $key ) = @_;
    $self->_loadStatus();
    return $self->{status}->{$key};
}

sub waitInput {
    my ( $self, $msg, $pipeFile ) = @_;

    my @opts;
    if ( $msg =~ /\(([\w\|]+)\)$/ ) {
        my $optLine = $1;
        @opts = split( /\|/, $optLine );
    }

    my $dbInfo = $self->{dbInfo};
    my $role   = $dbInfo->{dbaRole};
    if ( defined($role) and $role eq '' ) {
        undef($role);
    }

    my $pipeDescJson = {
        pipeFile => $pipeFile,
        message  => $msg,
        title    => 'Choose the action',
        opType   => 'button',
        role     => $role,
        options  => \@opts
    };

    $self->updateStatus( interact => $pipeDescJson, status => 'waitInput' );

    return DeployUtils->decideOption( $msg, $pipeFile, $role );
}

1;

