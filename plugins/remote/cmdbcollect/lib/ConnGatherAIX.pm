#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

use strict;

package ConnGatherAIX;

#use parent 'ConnGatherBase';    #继承BASECollector
use ConnGatherBase;
our @ISA = qw(ConnGatherBase);

sub new {
    my ($type) = @_;
    my $self = {};
    bless( $self, $type );

    my $lsnPortsMap = $self->getListenPorts();
    $self->{lsnPortsMap} = $lsnPortsMap;
    $self->{remoteAddrs} = $self->getRemoteAddrs($lsnPortsMap);

    return $self;
}

sub findSockPid {
    my ( $self, $sockAddr ) = @_;

    my $pid;
    my $sockRefTxt = `rmsock $sockAddr tcpcb`;

    #The socket 0xf1000e0000f26008 is being held by proccess 4063332 (sshd).
    if ( $sockRefTxt =~ /\s+(\d+)\s+/ ) {
        $pid = $1;
    }

    return $pid;
}

sub parseListenLines {
    my ( $self, %args ) = @_;

    my $cmd         = $args{cmd};
    my $lsnFieldIdx = $args{lsnFieldIdx};
    my $sockAddrIdx = 0;

    my $portsMap = {};
    my $status   = 0;
    my $pipe;
    my $pid = open( $pipe, $cmd );
    if ( defined($pipe) ) {
        my $line;
        while ( $line = <$pipe> ) {
            my @fields     = split( /\s+/, $line );
            my $sockAddr   = $fields[$sockAddrIdx];
            my $listenAddr = $fields[$lsnFieldIdx];
            if ( $listenAddr =~ /^(.*)\.(\d+)$/ ) {
                my $ip   = $1;
                my $port = $2;

                my $pid = $self->findSockPid($sockAddr);

                if ( $ip eq '*' ) {
                    $portsMap->{$port} = $pid;
                }
                else {
                    $portsMap->{$listenAddr} = $pid;
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
    my $pid            = $args{pid};

    my $remoteAddrs = {};
    my $status      = 0;
    my $pipe;
    my $pipePid = open( $pipe, $cmd );
    if ( defined($pipe) ) {
        my $line;
        while ( $line = <$pipe> ) {
            my @fields     = split( /\s+/, $line );
            my $sockAddr   = $fields[0];
            my $localAddr  = $fields[$localFieldIdx];
            my $remoteAddr = $fields[$remoteFieldIdx];
            if ( $localAddr =~ /^(.*)\.(\d+)$/ ) {
                my $ip   = $1;
                my $port = $2;

                if ( $remoteAddr =~ /^(.+)\.(\d+)$/ ) {
                    my $addr = $1;
                    my $port = $2;
                    if (    not defined( $lsnPortsMap->{$localAddr} )
                        and not defined( $lsnPortsMap->{$port} ) )
                    {
                        my $useByPid = $self->findSockPid($sockAddr);
                        if ( not defined($pid) or $useByPid == $pid ) {
                            $remoteAddrs->{$remoteAddr} = "$addr:$port";
                        }
                    }
                }
            }
        }
        close($pipe);
        $status = $?;
    }

    return ( $status, $remoteAddrs );
}

sub getRemoteAddrs {
    my ( $self, $lsnPortsMap ) = @_;

    my $remoteAddrs    = {};
    my $status         = 0;
    my $cmd            = "netstat -Aan | grep -v LISTEN |";
    my $localFieldIdx  = 4;
    my $remoteFieldIdx = 5;
    ( $status, $remoteAddrs ) = $self->parseConnLines(
        cmd            => $cmd,
        lsnPortsMap    => $lsnPortsMap,
        localFieldIdx  => $localFieldIdx,
        remoteFieldIdx => $remoteFieldIdx
    );

    return $remoteAddrs;
}

sub getListenPorts {
    my ($self) = @_;

    #AIX
    #netstat -Aan | grep LISTEN |
    my $portsMap    = {};
    my $status      = 0;
    my $cmd         = "netstat -Aan | grep LISTEN |";
    my $lsnFieldIdx = 4;
    ( $status, $portsMap ) = $self->parseListenLines(
        cmd         => $cmd,
        lsnFieldIdx => $lsnFieldIdx
    );

    return $portsMap;
}

#获取单个进程的连出的TCP/UDP连接
sub getConnInfo {
    my ( $self, $pid ) = @_;
    my $lsnPortsMap = $self->{lsnPortsMap};
    my $remoteAddrs = $self->{remoteAddrs};

    my $connInfo    = {};
    my $lsnPortsMap = {};
    while ( my ( $lsnPort, $useByPid ) = each(%$lsnPortsMap) ) {
        if ( $useByPid == $pid ) {
            $lsnPortsMap->{$lsnPort} = 1;
        }
    }

    my $remoteAddrsMap = {};
    while ( my ( $remoteAddr, $useByPid ) = each(%$remoteAddrs) ) {
        if ( $useByPid == $pid ) {
            $remoteAddrsMap->{$remoteAddr} = 1;
        }
    }

    $connInfo->{LISTEN} = $lsnPortsMap;
    $connInfo->{PEER}   = $remoteAddrsMap;

    return $connInfo;
}

1;
