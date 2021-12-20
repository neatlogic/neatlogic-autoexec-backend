#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package ConnGatherBase;

use strict;
use FindBin;
use POSIX qw(:sys_wait_h WNOHANG setsid uname);
use Data::Dumper;

sub new {
    my ( $type, $inspect ) = @_;
    my $self = {};
    $self->{inspect} = $inspect;
    bless( $self, $type );
    return $self;
}

sub parseListenLines {
    my ( $self, %args ) = @_;
    print("INFO: Try to collect process listen addressses.\n");
    my $cmd         = $args{cmd};
    my $pid         = $args{pid};
    my $lsnFieldIdx = $args{lsnFieldIdx};

    my $portsMap = {};
    my $status   = 0;
    my $pipe;
    my $pipePid = open( $pipe, $cmd );
    if ( defined($pipe) ) {
        my $line;
        while ( $line = <$pipe> ) {
            if ( rindex( $line, $pid ) < 0 ) {
                next;
            }

            my @fields = split( /\s+/, $line );
            my $lastIdx = $#fields;
            if ( index( $fields[$lastIdx], $pid ) < 0 ) {
                next;
            }

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
    print("INFO: Try to collect process connections.\n");
    my $cmd            = $args{cmd};
    my $pid            = $args{pid};
    my $localFieldIdx  = $args{localFieldIdx};
    my $remoteFieldIdx = $args{remoteFieldIdx};
    my $recvQIdx       = $args{recvQIdx};
    my $sendQIdx       = $args{sendQIdx};
    my $lsnPortsMap    = $args{lsnPortsMap};

    my $totalCount         = 0;
    my $inBoundCount       = 0;
    my $outBoundCount      = 0;
    my $recvQNoneZeroCount = 0;
    my $sendQNoneZeroCount = 0;
    my $totalRecvQSize     = 0;
    my $totalSendQSize     = 0;
    my $outBoundStats      = {};

    my $remoteAddrs = {};
    my $status      = 0;
    my $pipe;
    my $pipePid = open( $pipe, $cmd );
    if ( defined($pipe) ) {
        my $line;
        while ( $line = <$pipe> ) {
            if ( rindex( $line, $pid ) < 0 ) {
                next;
            }

            my @fields = split( /\s+/, $line );
            my $lastIdx = $#fields;
            if ( index( $fields[$lastIdx], $pid ) < 0 ) {
                next;
            }

            my $localAddr  = $fields[$localFieldIdx];
            my $remoteAddr = $fields[$remoteFieldIdx];
            $localAddr =~ s/^::ffff:(\d+\.)/$1/;
            $localAddr =~ s/0000:0000:0000:0000:0000:ffff:(\d+\.)/$1/;
            $remoteAddr =~ s/^::ffff:(\d+\.)/$1/;
            $remoteAddr =~ s/0000:0000:0000:0000:0000:ffff:(\d+\.)/$1/;

            if ( $localAddr =~ /^(.*):(\d+)$/ ) {
                my $ip        = $1;
                my $port      = $2;
                my $recvQSize = int( $fields[$recvQIdx] );
                my $sendQSize = int( $fields[$sendQIdx] );

                if (    $remoteAddr =~ /:\d+$/
                    and not defined( $lsnPortsMap->{$localAddr} )
                    and not defined( $lsnPortsMap->{$port} ) )
                {
                    $outBoundCount = $outBoundCount + 1;
                    $remoteAddrs->{$remoteAddr} = 1;

                    if ( $self->{inspect} == 1 ) {
                        my $outBoundStat = $outBoundStats->{$remoteAddr};
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
                else {
                    $inBoundCount = $inBoundCount + 1;
                }

                $totalCount     = $totalCount + 1;
                $totalRecvQSize = $totalRecvQSize + $recvQSize;
                $totalSendQSize = $totalSendQSize + $sendQSize;
                if ( $recvQSize > 0 ) {
                    $recvQNoneZeroCount = $recvQNoneZeroCount + 1;
                }
                if ( $sendQSize > 0 ) {
                    $sendQNoneZeroCount = $sendQNoneZeroCount + 1;
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

    my $connStatInfo = {
        'TOTAL_COUNT'       => $totalCount,
        'INBOUND_COUNT'     => $inBoundCount,
        'OUTBOUND_COUNT'    => $outBoundCount,
        'RECV_QUEUED_COUNT' => $recvQNoneZeroCount,
        'SEND_QUEUED_COUNT' => $sendQNoneZeroCount,
        'RECV_QUEUED_SIZE'  => $totalRecvQSize,
        'SEND_QUEUED_SIZE'  => $totalSendQSize,
        'OUTBOUND_STATS'    => $outBoundStats
    };

    return ( $status, $remoteAddrs, $connStatInfo );
}

sub getRemoteAddrs {
    my ( $self, $lsnPortsMap, $pid ) = @_;

    my $remoteAddrs  = {};
    my $connStatInfo = {};
    my $status       = 3;

    if ( $status != 0 ) {
        my $cmd            = "netstat -ntudwp|";
        my $localFieldIdx  = 3;
        my $remoteFieldIdx = 4;
        ( $status, $remoteAddrs, $connStatInfo ) = $self->parseConnLines(
            cmd            => $cmd,
            pid            => $pid,
            lsnPortsMap    => $lsnPortsMap,
            localFieldIdx  => $localFieldIdx,
            remoteFieldIdx => $remoteFieldIdx,
            recvQIdx       => 1,
            sendQIdx       => 2
        );
    }

    if ( $status != 0 ) {
        my $cmd            = "ss -ntudwp |";
        my $localFieldIdx  = 4;
        my $remoteFieldIdx = 5;
        ( $status, $remoteAddrs, $connStatInfo ) = $self->parseConnLines(
            cmd            => $cmd,
            pid            => $pid,
            lsnPortsMap    => $lsnPortsMap,
            localFieldIdx  => $localFieldIdx,
            remoteFieldIdx => $remoteFieldIdx,
            recvQIdx       => 2,
            sendQIdx       => 3
        );
    }

    return ( $remoteAddrs, $connStatInfo );
}

sub getListenPorts {
    my ( $self, $pid ) = @_;

    #Linux
    #ss -ntudwlp | grep pid=<pid>
    #netstat -tuwnlp |grep <pid>
    my $portsMap = {};
    my $status   = 3;

    if ( $status != 0 ) {
        my $cmd         = "netstat -ntudwlp |";
        my $lsnFieldIdx = 3;
        ( $status, $portsMap ) = $self->parseListenLines(
            cmd         => $cmd,
            pid         => $pid,
            lsnFieldIdx => $lsnFieldIdx
        );
    }

    if ( $status != 0 ) {
        my $cmd         = "ss -ntudwlp |";
        my $lsnFieldIdx = 4;
        ( $status, $portsMap ) = $self->parseListenLines(
            cmd         => $cmd,
            pid         => $pid,
            lsnFieldIdx => $lsnFieldIdx
        );
    }

    return $portsMap;
}

#获取单个进程的连出的TCP/UDP连接
sub getConnInfo {
    my ( $self, $pid ) = @_;
    my $lsnPortsMap = $self->getListenPorts($pid);
    my ( $remoteAddrs, $connStatInfo ) = $self->getRemoteAddrs( $lsnPortsMap, $pid );

    my $connInfo = {};
    $connInfo->{LISTEN} = $lsnPortsMap;
    $connInfo->{PEER}   = $remoteAddrs;
    $connInfo->{STATS}  = $connStatInfo;

    return $connInfo;
}

1;
