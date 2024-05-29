#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package LinuxPS;

use strict;
use POSIX;

use IO::File;

sub new {
    my ($type) = @_;

    #PID PPID PGID USER GID RUSER RGID %CPU %MEM TIME ELAPSED COMM ARGS
    my $self = {
        hasInit   => 0,
        processes => []
    };

    bless( $self, $type );

    return $self;
}

sub init {
    my ($self) = @_;
    if ( $self->{hasInit} == 0 ) {
        $self->{totalMem} = $self->_getTotalMemSize();
        $self->{uptime}   = $self->_getUptime();
        my $tickRate = `getconf CLK_TCK`;
        $self->{tickRate}    = int($tickRate);
        $self->{processList} = $self->_getAllProceses();
        $self->{hasInit}     = 1;
    }
}

sub getProcessList {
    my ($self) = @_;
    $self->init();
    return $self->{processList};
}

sub _convert2kb {
    my ( $self, $size, $unit ) = @_;
    $size = int($size);
    $unit = lc($unit);
    if ( index( $unit, 'm' ) >= 0 ) {
        $size = $size * 1024;
    }
    elsif ( index( $unit, 'g' ) >= 0 ) {
        $size = $size * 1024 * 1024;
    }
    elsif ( index( $unit, 't' ) >= 0 ) {
        $size = $size * 1024 * 1024 * 1024;
    }
    elsif ( index( $unit, 'p' ) >= 0 ) {
        $size = $size * 1024 * 1024 * 1024 * 1024;
    }

    return $size;
}

sub _convertSec2Time {
    my ( $self, $epochTime ) = @_;
    my $timeStr = '';
    $timeStr   = sprintf( "%02s", $epochTime % 60 );
    $epochTime = int( $epochTime / 60 );
    $timeStr   = sprintf( "%02s:%s", $epochTime % 60, $timeStr );
    $epochTime = int( $epochTime / 60 );
    $timeStr   = sprintf( "%02s:%s", $epochTime % 60, $timeStr );
    $epochTime = int( $epochTime / 60 );

    my $days = $epochTime % 24;
    if ( $days > 0 ) {
        $timeStr = sprintf( "%s-%s", $days, $timeStr );
    }

    return $timeStr;
}

sub _getTotalMemSize {
    my ($self)   = @_;
    my $memTotal = ~0;
    my $memPath  = "/proc/meminfo";
    my $fh       = IO::File->new("<$memPath");
    if ( not defined($fh) ) {
        print("WARN: Open file $memPath failed:$!\n");
        return;
    }
    while ( my $line = $fh->getline() ) {
        my @fields = split( /[:\s]+/, $line );
        if ( $fields[0] eq 'MemTotal' ) {
            $memTotal = $self->_convert2kb( $fields[1], $fields[2] );
        }
    }
    $fh->close();

    return $memTotal;
}

sub _getUptime {
    my ($self)     = @_;
    my $uptime     = ~0;
    my $uptimePath = "/proc/uptime";
    my $fh         = IO::File->new("<$uptimePath");
    if ( not defined($fh) ) {
        print("WARN: Open file $uptimePath failed:$!\n");
        return;
    }
    my $line;
    $fh->read( $line, 64 );
    my @fields = split( /\s+/, $line, 2 );
    $uptime = $fields[0] + 0.0;

    $fh->close();

    return $uptime;
}

sub _getAllProceses {
    my ($self) = @_;

    my @processes = ();
    my $dh;
    opendir( $dh, '/proc' );
    if ( not defined($dh) ) {
        print("WARN: Open directory /proc failed:$!\n");
        return;
    }

    while ( my $pid = readdir($dh) ) {
        if ( $pid =~ /^\d+$/ ) {
            my $procArray = $self->_getProcess($pid);
            if ( defined($procArray) ) {
                push( @processes, $procArray );
            }
        }
    }
    closedir($dh);

    return \@processes;
}

sub _getProcess {
    my ( $self, $pid ) = @_;

    my $tickRate = $self->{tickRate};
    my $uptime   = $self->{uptime};

    my $statPath = "/proc/$pid/stat";
    my $fh       = IO::File->new("<$statPath");
    if ( not defined($fh) ) {
        print("WARN: Open file $statPath failed:$!\n");
        return;
    }

    my @statFields = split( /\s+/, $fh->getline() );
    my $ppid       = $statFields[3];
    my $pgid       = $statFields[4];
    my $utime      = $statFields[14];
    my $stime      = $statFields[15];
    my $comm       = substr( $statFields[1], 1, -1 );
    my $time       = $self->_convertSec2Time( ( $utime + $stime ) / $tickRate );
    my $starttime  = $statFields[22] / $tickRate;
    my $elapsed    = $uptime - $starttime;
    my $pcpu       = int( ( $utime + $stime ) * 10000 / $tickRate / $uptime ) / 100;

    $fh->close();

    my $cmdPath = "/proc/$pid/cmdline";
    my $fh      = IO::File->new("<$cmdPath");
    if ( not defined($fh) ) {
        print("WARN: Open file $cmdPath failed:$!\n");
        return;
    }
    my $command = $fh->getline();
    $command =~ s/\x0/ /g;
    $fh->close();

    my $statusPath = "/proc/$pid/status";
    my $fh         = IO::File->new("<$statusPath");
    if ( not defined($fh) ) {
        print("WARN: Open file $statusPath failed:$!\n");
        return;
    }
    my ( $user, $ruser, $gid, $rgid, $pmem );
    my $statusInfo = {};
    while ( my $line = $fh->getline() ) {
        my @statusFields = split( /[:\s]+/, $line );
        if ( $statusFields[0] eq 'Uid' ) {
            $ruser = getpwuid( $statusFields[1] );
            $user  = getpwuid( $statusFields[2] );
        }
        elsif ( $statusFields[0] eq 'Gid' ) {
            $rgid = $statusFields[1];
            $gid  = $statusFields[2];
        }
        elsif ( $statusFields[0] eq 'VmRSS' ) {
            my $rss = $self->_convert2kb( $statusFields[1], $statusFields[2] );
            $pmem = int( $rss * 10000 / $self->{totalMem} ) / 100;
        }
    }

    $fh->close();

    #PID PPID PGID USER GID RUSER RGID %CPU %MEM TIME ELAPSED COMM ARGS
    return [ $pid, $ppid, $pgid, $user, $gid, $ruser, $rgid, $pcpu, $pmem, $time, $elapsed, $comm, $command ];
}

1;
