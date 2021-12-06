#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package ConnGatherBase;

use strict;
use FindBin;
use POSIX qw(:sys_wait_h WNOHANG setsid uname);
use Data::Dumper;

sub new {
    my ($type) = @_;
    my $self = {};
    bless( $self, $type );
    return $self;
}

sub parseListenLines {
    my ( $self, %args ) = @_;
    print("INFO: Try to connect process listen addressses.\n");
    my $cmd         = $args{cmd};
    my $lsnFieldIdx = $args{lsnFieldIdx};

    my $portsMap = {};
    my $status   = 0;
    my $pipe;
    my $pid = open( $pipe, $cmd );
    if ( defined($pipe) ) {
        my $line;
        while ( $line = <$pipe> ) {
            my @fields = split( /\s+/, $line );
            my $listenAddr = $fields[$lsnFieldIdx];
            $listenAddr =~ s/^::ffff:(\d+\.)/$1/;
            $listenAddr =~ s/0000:0000:0000:0000:0000:ffff:(\d+\.)/$1/;

            if ( $listenAddr =~ /^(.*):(\d+)$/ ) {
                my $ip   = $1;
                my $port = $2;
                if ( $ip eq '*' or $ip eq '::' or $ip eq '[::]' or $ip eq '0.0.0.0' ) {
                    $portsMap->{$port} = 1;
                }
                else {
                    $portsMap->{$listenAddr} = 1;
                }
            }
        }
        close($pipe);
        $status = $?;
        print("INFO: Collect process listen addressses complete.\n");
    }
    else {
        $status = -1;
        print("ERROR: Can not launch command:$cmd to collect process listen addressses.\n");
    }

    return ( $status, $portsMap );
}

sub parseConnLines {
    my ( $self, %args ) = @_;
    print("INFO: Try to connect process connections.\n");
    my $cmd            = $args{cmd};
    my $localFieldIdx  = $args{localFieldIdx};
    my $remoteFieldIdx = $args{remoteFieldIdx};
    my $lsnPortsMap    = $args{lsnPortsMap};

    my $remoteAddrs = {};
    my $status      = 0;
    my $pipe;
    my $pid = open( $pipe, $cmd );
    if ( defined($pipe) ) {
        my $line;
        while ( $line = <$pipe> ) {
            my @fields     = split( /\s+/, $line );
            my $localAddr  = $fields[$localFieldIdx];
            my $remoteAddr = $fields[$remoteFieldIdx];
            $localAddr =~ s/^::ffff:(\d+\.)/$1/;
            $localAddr =~ s/0000:0000:0000:0000:0000:ffff:(\d+\.)/$1/;
            $remoteAddr =~ s/^::ffff:(\d+\.)/$1/;
            $remoteAddr =~ s/0000:0000:0000:0000:0000:ffff:(\d+\.)/$1/;

            if ( $localAddr =~ /^(.*):(\d+)$/ ) {
                my $ip   = $1;
                my $port = $2;

                if (    $remoteAddr =~ /:\d+$/
                    and not defined( $lsnPortsMap->{$localAddr} )
                    and not defined( $lsnPortsMap->{$port} ) )
                {
                    $remoteAddrs->{$remoteAddr} = 1;
                }
            }
        }
        close($pipe);
        $status = $?;
        print("INFO: Collect process connections complete.\n");
    }
    else {
        $status = -1;
        print("ERROR: Can not launch command: $cmd to collect process connections.\n");
    }

    return ( $status, $remoteAddrs );
}

sub getRemoteAddrs {
    my ( $self, $lsnPortsMap, $pid ) = @_;

    my $remoteAddrs = {};
    my $status      = 3;

    if ( $status != 0 ) {
        my $cmd            = "netstat -ntudwp| grep $pid |";
        my $localFieldIdx  = 3;
        my $remoteFieldIdx = 4;
        ( $status, $remoteAddrs ) = $self->parseConnLines(
            cmd            => $cmd,
            lsnPortsMap    => $lsnPortsMap,
            localFieldIdx  => $localFieldIdx,
            remoteFieldIdx => $remoteFieldIdx
        );
    }

    if ( $status != 0 ) {
        my $cmd            = "ss -ntudwp| grep pid=$pid |";
        my $localFieldIdx  = 4;
        my $remoteFieldIdx = 5;
        ( $status, $remoteAddrs ) = $self->parseConnLines(
            cmd            => $cmd,
            lsnPortsMap    => $lsnPortsMap,
            localFieldIdx  => $localFieldIdx,
            remoteFieldIdx => $remoteFieldIdx
        );
    }

    return $remoteAddrs;
}

sub getListenPorts {
    my ( $self, $pid ) = @_;

    #Linux
    #ss -ntudwlp | grep pid=<pid>
    #netstat -tuwnlp |grep <pid>
    my $portsMap = {};
    my $status   = 3;

    if ( $status != 0 ) {
        my $cmd         = "netstat -ntudwlp| grep $pid |";
        my $lsnFieldIdx = 3;
        ( $status, $portsMap ) = $self->parseListenLines(
            cmd         => $cmd,
            lsnFieldIdx => $lsnFieldIdx
        );
    }

    if ( $status != 0 ) {
        my $cmd         = "ss -ntudwlp| grep pid=$pid |";
        my $lsnFieldIdx = 4;
        ( $status, $portsMap ) = $self->parseListenLines(
            cmd         => $cmd,
            lsnFieldIdx => $lsnFieldIdx
        );
    }

    return $portsMap;
}

#获取单个进程的连出的TCP/UDP连接
sub getConnInfo {
    my ( $self, $pid ) = @_;
    my $lsnPortsMap = $self->getListenPorts($pid);
    my $remoteAddrs = $self->getRemoteAddrs( $lsnPortsMap, $pid );

    my $connInfo = {};
    $connInfo->{LISTEN} = $lsnPortsMap;
    $connInfo->{PEER}   = $remoteAddrs;

    return $connInfo;
}

1;
