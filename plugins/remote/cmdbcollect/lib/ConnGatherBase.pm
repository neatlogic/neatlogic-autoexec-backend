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
            if ( $listenAddr =~ /^(.*):(\d+)$/ ) {
                my $ip   = $1;
                my $port = $2;
                if ( $ip eq '*' or $ip eq '::' ) {
                    $portsMap->{$port} = 1;
                }
                else {
                    $portsMap->{$listenAddr} = 1;
                }
            }
        }
        close($pipe);
        $status = $?;
    }

    return ( $status, $portsMap );
}

sub parseConnLines {
    my ( $self, %args ) = @_;

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
    }

    return ( $status, $remoteAddrs );
}

sub getRemoteAddrs {
    my ( $self, $lsnPortsMap, $pid ) = @_;

    my $remoteAddrs    = {};
    my $status         = 0;
    my $cmd            = "ss -ntudwp| grep pid=$pid |";
    my $localFieldIdx  = 4;
    my $remoteFieldIdx = 5;
    ( $status, $remoteAddrs ) = $self->parseConnLines(
        cmd            => $cmd,
        lsnPortsMap    => $lsnPortsMap,
        localFieldIdx  => $localFieldIdx,
        remoteFieldIdx => $remoteFieldIdx
    );

    if ( $status != 0 ) {
        $cmd            = "netstat -ntudwp| grep $pid |";
        $localFieldIdx  = 3;
        $remoteFieldIdx = 4;
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
    my $portsMap    = {};
    my $status      = 0;
    my $cmd         = "ss -ntudwlp| grep pid=$pid |";
    my $lsnFieldIdx = 4;
    ( $status, $portsMap ) = $self->parseListenLines(
        cmd         => $cmd,
        lsnFieldIdx => $lsnFieldIdx
    );
    if ( $status != 0 ) {
        $cmd         = "netstat -ntudwlp| grep $pid |";
        $lsnFieldIdx = 3;
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
