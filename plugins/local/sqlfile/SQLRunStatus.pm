#!/usr/bin/perl
use FindBin;

#use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
#use lib "$FindBin::Bin/../lib";

package SQLRunStatus;

use strict;
use IO::File;
use File::Basename;
use File::Path;

sub new {
    my ( $pkg, $logPath, $logPrefix, $timeSpan, $statusPathPrefix ) = @_;
    my $self = {};

    $self->{'logPath'}   = $logPath;
    $self->{'logPrefix'} = $logPrefix;

    #$self->{'sucStatusPath'} = "$statusPathPrefix.suc";

    #初始化日志
    if ( not defined($timeSpan) ) {
        $timeSpan = $ENV{RUN_TIMESPAN};
    }

    my $logName = "$logPrefix.$timeSpan.log";
    $self->{'logName'} = $logName;

    my $linkPath = "$logPath/$logPrefix.log";
    $self->{'linkPath'} = $linkPath;

    my $preLogName = $ENV{RUN_PRELOGNAME};

    if ( not defined($preLogName) or $preLogName eq '' ) {
        if ( -l $linkPath or -e $linkPath ) {
            $preLogName = readlink($linkPath);
        }
    }
    $self->{preLogName} = $preLogName;

    if ( $logName ne $preLogName ) {
        unlink($linkPath);
        symlink( $logName, $linkPath );
    }

    #初始化状态记录
    my $logFH = new IO::File(">>$logPath/$logName");
    if ( defined($logFH) ) {
        $logFH->autoflush(1);
        $self->{'logFH'} = $logFH;
    }
    else {
        die("can not create log file:$logPath/$logName $!");
    }

    my $hisStatusFilePath = "$logPath/$logPrefix.$timeSpan.status";
    $self->{hisStatusFilePath} = $hisStatusFilePath;

    my $statusFilePath = "$statusPathPrefix.status";
    my $statusPath     = dirname($statusFilePath);
    if ( not -e $statusPath ) {
        mkpath($statusPath);
    }
    else {
        my $content;
        my $size = -s $statusFilePath;
        my $fh   = new IO::File("<$statusFilePath");

        if ( defined($fh) ) {
            $fh->read( $content, $size );
            $fh->close();
        }

        $self->{statusFilePath}   = $statusFilePath;
        $self->{preStatusContent} = $content;
    }

    my $statusFH = new IO::File("+>>$statusFilePath");
    if ( defined($statusFH) ) {
        $statusFH->autoflush(1);
        $statusFH->truncate(0);
        print $statusFH ('pending');
        $self->{'statusFH'} = $statusFH;
    }
    else {
        die("Can not create status file:$statusFilePath, $!");
    }

    my $hisStatusFH = new IO::File("+>>$hisStatusFilePath");
    if ( defined($hisStatusFH) ) {
        $hisStatusFH->autoflush(1);
        $hisStatusFH->truncate(0);
        print $hisStatusFH ('pending');
        $self->{'hisStatusFH'} = $hisStatusFH;
    }
    else {
        die("Can not create status file:$hisStatusFilePath, $!");
    }

    Utils::sigHandler(
        'TERM', 'INT', 'HUP', 'ABRT',
        sub {
            if ( defined($statusFH) ) {
                $statusFH->truncate(0);
                print $statusFH ('aborted');
                $statusFH->close();
            }

            #my $sucStatusFile = $self->{'sucStatusPath'};
            #if ( -e $sucStatusFile ) {
            #    unlink($sucStatusFile);
            #}

            Utils::setErrFlag(134);
            return (-1);
        }
    );

    bless( $self, $pkg );

    return $self;
}

sub getLogHandle {
    my ($self) = @_;
    return $self->{logFH};
}

sub start {
    my ($self) = @_;
    my $statusFH = $self->{statusFH};
    if ( defined($statusFH) ) {
        $statusFH->truncate(0);
        print $statusFH ('running');
    }

    my $hisStatusFH = $self->{hisStatusFH};
    if ( defined($hisStatusFH) ) {
        $hisStatusFH->truncate(0);
        print $hisStatusFH ('running');
    }
}

sub abort {
    my ( $self, $warnCount ) = @_;
    $self->endWithStatus( 'aborted', $warnCount );
}

sub suc {
    my ( $self, $warnCount, $hasError ) = @_;
    $self->endWithStatus( 'succeed', $warnCount, $hasError );
}

sub fail {
    my ( $self, $warnCount ) = @_;
    $self->endWithStatus( 'failed', $warnCount );
}

sub endWithStatus {
    my ( $self, $status, $warnCount, $hasError ) = @_;
    my $logFH = $self->{logFH};
    if ( defined($logFH) ) {
        $logFH->close();
    }

    my $statusFH = $self->{statusFH};
    if ( defined($statusFH) ) {
        $statusFH->truncate(0);

        if ( not defined($hasError) ) {
            $hasError = 0;
        }

        print $statusFH ("$status\n$warnCount\n$hasError");

        $statusFH->close();
        $self->{'statusFH'} = undef;
    }

    my $hisStatusFH = $self->{hisStatusFH};
    if ( defined($hisStatusFH) ) {
        $hisStatusFH->truncate(0);

        if ( not defined($hasError) ) {
            $hasError = 0;
        }

        print $hisStatusFH ("$status\n$warnCount\n$hasError");

        $hisStatusFH->close();
        $self->{'hisStatusFH'} = undef;
    }
}

sub restorePreLog {
    my ($self) = @_;

    #print("DEBUG: status file path:$self->{statusFilePath}\n");
    my $statusFilePath = $self->{statusFilePath};
    my $fh             = IO::File->new(">$statusFilePath");
    if ( defined($fh) ) {

        #print("DEBUG: $self->{preStatusContent}\n");
        print $fh ( $self->{preStatusContent} );
        $fh->close();
    }
    else {
        die("ERROR: write to file $statusFilePath failed:$!\n");
    }

    #显示效果容易引起误解，取消此功能
    #my $linkPath = $self->{linkPath};
    #if ( -l $linkPath or -e $linkPath ) {
    #    unlink($linkPath);
    #}

    #symlink( $self->{preLogName}, $linkPath );
    ##############################

    my $logFH = $self->{logFH};

    if ( defined($logFH) ) {
        $logFH->close();
    }
}

sub getStatusAndWarnCount {
    my ($statusPath) = @_;
    my $fh = new IO::File("<$statusPath");
    if ( defined($fh) ) {
        my $status = $fh->getline();
        chomp($status);
        my $warnCount = int( $fh->getline() );
        my $hasError  = int( $fh->getline() );
        $fh->close();
        return ( $status, $warnCount, $hasError );
    }
}

sub getStatus {
    my ($statusPath) = @_;
    my $fh = new IO::File("<$statusPath");
    if ( defined($fh) ) {
        my $status = $fh->getline();
        chomp($status);
        $fh->close();
        return $status;
    }
}

sub setStatus {
    my ( $statusPath, $status ) = @_;
    my $fh = new IO::File(">$statusPath");
    if ( defined($fh) ) {
        print $fh ($status);
        $fh->close();
    }
}

1;

