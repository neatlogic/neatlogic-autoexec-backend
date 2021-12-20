#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

use strict;

package ConnGatherAIX;

#use parent 'ConnGatherBase';    #继承BASECollector
use ConnGatherBase;
our @ISA = qw(ConnGatherBase);

sub new {
    my ( $type, $inspect ) = @_;
    my $self = {};
    $self->{inspect} = $inspect;
    bless( $self, $type );

    $self->{procConnStats} = {};
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
    print("INFO: Begin to collect process listen addresses.\n");
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
            $listenAddr =~ s/^::ffff:(\d+\.)/$1/;
            $listenAddr =~ s/0000:0000:0000:0000:0000:ffff:(\d+\.)/$1/;

            if ( $listenAddr =~ /^(.*)\.(\d+)$/ ) {
                my $ip   = $1;
                my $port = $2;

                my $pid = $self->findSockPid($sockAddr);

                if ( $ip eq '*' or $ip eq '::' or $ip eq '[::]' or $ip eq '0.0.0.0' ) {
                    $portsMap->{$port} = $pid;
                }
                else {
                    $portsMap->{$listenAddr} = $pid;
                }
            }
        }
        close($pipe);
        $status = $?;
        print("INFO: Collect process listen addresses complete.\n");
    }
    else {
        $status = -1;
        print("ERROR: Can not launch command:$cmd to collection listen addresses.\n");
    }

    return ( $status, $portsMap );
}

sub processConnStat {
    my ( $self, $pid, $isInBound, $fields, $recvQIdx, $sendQIdx, $remoteAddr ) = @_;

    my $myConnStats = $self->{procConnStats}->{$pid};
    if ( not defined($myConnStats) ) {
        $myConnStats = {
            'TOTAL_COUNT'       => 0,
            'INBOUND_COUNT'     => 0,
            'OUTBOUND_COUNT'    => 0,
            'RECV_QUEUED_COUNT' => 0,
            'SEND_QUEUED_COUNT' => 0,
            'RECV_QUEUED_SIZE'  => 0,
            'SEND_QUEUED_SIZE'  => 0,
            'OUTBOUND_STATS'    => {}
        };
        $self->{procConnStats}->{$pid} = $myConnStats;
    }

    my $recvQSize = int( $$fields[$recvQIdx] );
    my $sendQSize = int( $$fields[$sendQIdx] );

    $myConnStats->{TOTAL_COUNT} = $myConnStats->{TOTAL_COUNT} + 1;

    $myConnStats->{RECV_QUEUED_SIZE} = $myConnStats->{RECV_QUEUED_SIZE} + $recvQSize;
    $myConnStats->{SEND_QUEUED_SIZE} = $myConnStats->{SEND_QUEUED_SIZE} + $sendQSize;

    if ( $recvQSize > 0 ) {
        $myConnStats->{RECV_QUEUED_COUNT} = $myConnStats->{RECV_QUEUED_COUNT} + 1;
    }
    if ( $sendQSize > 0 ) {
        $myConnStats->{SEND_QUEUED_COUNT} = $myConnStats->{SEND_QUEUED_COUNT} + 1;
    }

    if ( $isInBound == 1 ) {
        $myConnStats->{INBOUND_COUNT} = $myConnStats->{INBOUND_COUNT} + 1;
    }
    else {
        $myConnStats->{OUTBOUND_COUNT} = $myConnStats->{OUTBOUND_COUNT} + 1;
        if ( $self->{inspect} == 1 ) {
            my $outBoundStats = $myConnStats->{OUTBOUND_STATS};
            my $outBoundStat  = $outBoundStats->{$remoteAddr};
            if ( not defined($outBoundStat) ) {
                $outBoundStat = { SEND_QUEUED_COUNT => 0 };
                $outBoundStats->{$remoteAddr} = $outBoundStat;
            }

            if ( $sendQSize > 0 ) {
                $outBoundStat->{SEND_QUEUED_COUNT} = $outBoundStat->{SEND_QUEUED_COUNT} + 1;
            }
            $outBoundStat->{OUTBOUND_COUNT}   = $outBoundStat->{OUTBOUND_COUNT} + 1;
            $outBoundStat->{SEND_QUEUED_SIZE} = $outBoundStat->{SEND_QUEUED_SIZE} + $sendQSize;
        }
    }
}

sub parseConnLines {
    my ( $self, %args ) = @_;
    print("INFO: Begin to collect process connections.\n");
    my $cmd            = $args{cmd};
    my $localFieldIdx  = $args{localFieldIdx};
    my $remoteFieldIdx = $args{remoteFieldIdx};
    my $recvQIdx       = $args{recvQIdx};
    my $sendQIdx       = $args{sendQIdx};
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
            $localAddr =~ s/^::ffff:(\d+\.)/$1/;
            $localAddr =~ s/0000:0000:0000:0000:0000:ffff:(\d+\.)/$1/;
            $remoteAddr =~ s/^::ffff:(\d+\.)/$1/;
            $remoteAddr =~ s/0000:0000:0000:0000:0000:ffff:(\d+\.)/$1/;

            if ( $localAddr =~ /^(.*)\.(\d+)$/ ) {
                my $ip   = $1;
                my $port = $2;

                if ( $remoteAddr =~ /^(.+)\.(\d+)$/ ) {
                    my $addr = $1;
                    my $port = $2;

                    my $lsnBindPid = $lsnPortsMap->{$localAddr};
                    if ( not defined($lsnBindPid) ) {
                        $lsnBindPid = $lsnPortsMap->{$localAddr};
                    }

                    if ( not defined($lsnBindPid) ) {
                        my $useByPid = $self->findSockPid($sockAddr);
                        if ( not defined($pid) or $useByPid == $pid ) {
                            my $realRemoteAddr = "$addr:$port";

                            #$remoteAddrs->{$remoteAddr} = "$addr:$port";
                            $remoteAddrs->{$realRemoteAddr} = 1;
                            $self->processConnStat( $useByPid, 0, \@fields, $recvQIdx, $sendQIdx, $realRemoteAddr );
                        }
                    }
                    else {
                        $self->processConnStat( $lsnBindPid, 1, \@fields, $recvQIdx, $sendQIdx );
                    }
                }
            }
        }
        close($pipe);
        $status = $?;
        print("INFO: Collect process connections complete.\n");
    }
    else {
        $status = -1;
        print("ERROR: Can not launch command:$cmd to collect process connections.\n");
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
        remoteFieldIdx => $remoteFieldIdx,
        recvQIdx       => 2,
        sendQIdx       => 3
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
    my $lsnPortsMap   = $self->{lsnPortsMap};
    my $remoteAddrs   = $self->{remoteAddrs};
    my $procConnStats = $self->{procConnStats};

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
    $connInfo->{STATS}  = $procConnStats->{$pid};

    return $connInfo;
}

1;
