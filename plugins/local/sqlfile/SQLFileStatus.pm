#!/usr/bin/perl

use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";

package SQLFileStatus;

use strict;
use POSIX qw(strftime);
use Fcntl qw(SEEK_SET O_RDWR O_CREAT O_DIRECT O_SYNC SEEK_SET F_RDLCK F_WRLCK F_UNLCK F_GETLK F_SETLK F_SETLKW);
use IO::File;
use Cwd;
use Digest::MD5;
use File::Basename;
use Getopt::Long;
use JSON;
use DBInfo;
use Utils;
use Data::Dumper;

sub new {
    my ( $type, $sqlFile, %args ) = @_;

    my $self = {
        sqlFile   => $sqlFile,
        dbInfo    => $args{dbInfo},
        istty     => $args{istty},
        jobPath   => $args{jobPath},
        phaseName => $args{phaseName},
        status    => {}
    };

    my $dbInfo    = $self->{dbInfo};
    my $statusDir = "$self->{jobPath}/status/$self->{phaseName}/$dbInfo->{host}-$dbInfo->{port}-$dbInfo->{dbName}";
    if ( not -e $statusDir ) {
        if ( not mkdir($statusDir) ) {
            die("ERROR: Create directory $statusDir failed $!\n");
        }
    }

    $self->{sqlPath}    = "$self->{jobPath}/sqlfile/$self->{phaseName}/$sqlFile";
    $self->{statusPath} = "$statusDir/$sqlFile.txt";
    my $sqlDir = dirname( $self->{statusPath} );
    if ( not -e $sqlDir ) {
        mkpath($sqlDir);
    }

    bless( $self, $type );

    my $newSqlFile = 1;
    if ( -f $self->{statusPath} ) {
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

sub _doFcntl {
    my ( $self, $fh, $operation, $flags ) = @_;

    my $ret = 0;

    if ( fcntl( $fh, $operation, $flags ) ) {
        $ret = 1;
    }
    else {
        if ( $!{EAGAIN} ) {
            if ( fcntl( $fh, $operation, $flags ) ) {
                $ret = 1;
            }
        }

        while ( $ret != 1 and $!{EINTR} ) {
            if ( fcntl( $fh, $operation, $flags ) ) {
                $ret = 1;
                last;
            }
        }
    }

    if ( $ret == 0 and not $!{EAGAIN} ) {
        my $lockFile = $self->{statusPath};
        print("WARN: Lock $lockFile error:$!.\n");
    }

    return $ret;
}

sub _lockStatus {
    my ( $self, $lockShare ) = @_;

    my $lockMod = F_WRLCK;
    if ( $lockShare eq 1 ) {
        $lockMod = F_RDLCK;
    }

    my $fh = $self->{statusFH};
    sysseek( $fh, 0, SEEK_SET );
    my $flags = pack( 'ssx4qqlx4', $lockMod, 0, 0, 0, 0 );

    $self->_doFcntl( $fh, F_SETLKW, $flags );
}

sub _unlockStatus {
    my ($self) = @_;

    my $fh = $self->{statusFH};
    sysseek( $fh, 0, SEEK_SET );
    my $flags = pack( 'ssx4qqlx4', F_UNLCK, 0, 0, 0, 0 );

    $self->_doFcntl( $fh, F_SETLKW, $flags );
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

    truncate( $fh, 0 );
    syswrite( $fh, $jsonStr );

    $self->_unlockStatus(0);
}

sub updateStatus {
    my ( $self, %args ) = @_;

    foreach my $key ( keys(%args) ) {
        $self->{status}->{$key} = $args{$key};
    }
    $self->_saveStatus();
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

1;

