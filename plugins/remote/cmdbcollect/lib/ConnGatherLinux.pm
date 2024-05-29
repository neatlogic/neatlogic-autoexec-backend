#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

use strict;

package ConnGatherLinux;

#use parent 'ConnGatherBase';    #继承BASECollector
use ConnGatherBase;
our @ISA = qw(ConnGatherBase);
use CollectUtils;
use LinuxNetStat;
use NSSwitcher;

sub new {
    my ( $type, $inspect ) = @_;
    my $self = {};
    $self->{inspect}      = $inspect;
    $self->{collectUtils} = CollectUtils->new();
    $self->{netstat}      = LinuxNetStat->new();

    bless( $self, $type );

    return $self;
}

sub parseListenLines {
    my ( $self, %args ) = @_;

    my $netstat = $self->{netstat};

    my $pid = $args{pid};
    print("INFO: Begin to collect process:$pid listen addresses.\n");

    my $portsMap = {};
    my $status   = 0;

    my $procLsnArray = $netstat->getProclistenTable($pid);
    foreach my $fields (@$procLsnArray) {

        #Proto Recv-Q Send-Q LocalIP localPort           ForeignIP ForeignPort         State       PID
        my $backlogQ   = int( $$fields[1] );
        my $listenIp   = $$fields[3];
        my $listenPort = $$fields[4];

        if ( $listenIp eq '::' or $listenIp eq '0.0.0.0' ) {
            $portsMap->{$listenPort} = $backlogQ;
        }
        else {
            $portsMap->{"$listenIp:$listenPort"} = $backlogQ;
        }
    }

    if (%$portsMap) {
        print("INFO: Collect process $pid listen addresses success.\n");
    }
    else {
        print("INFO: Process $pid is not listened any addresses.\n");
    }

    return ( $status, $portsMap );
}

sub parseConnLines {
    my ( $self, %args ) = @_;

    my $netstat = $self->{netstat};

    my $pid = $args{pid};

    print("INFO: Try to collect process $pid connections.\n");

    my $lsnPortsMap = $args{lsnPortsMap};

    my $totalCount         = 0;
    my $inBoundCount       = 0;
    my $outBoundCount      = 0;
    my $synRecvCount       = 0;
    my $closeWaitCount     = 0;
    my $recvQNoneZeroCount = 0;
    my $sendQNoneZeroCount = 0;
    my $totalRecvQSize     = 0;
    my $totalSendQSize     = 0;
    my $outBoundStats      = {};

    my $remoteAddrs = {};
    my $status      = 0;

    my $procConnTable = $netstat->getProcConnTable($pid);
    foreach my $fields (@$procConnTable) {

        #Proto Recv-Q Send-Q LocalIP localPort           ForeignIP ForeignPort         State       PID
        my $localIp   = $$fields[3];
        my $localPort = $$fields[4];
        my $localAddr = "$localIp:$localPort";

        my $remoteIp   = $$fields[5];
        my $remotePort = $$fields[6];
        my $remoteAddr = "$remoteIp:$remotePort";

        my $connStatus = $$fields[7];
        my $recvQSize  = $$fields[2];
        my $sendQSize  = $$fields[3];

        if (    not defined( $lsnPortsMap->{$localAddr} )
            and not defined( $lsnPortsMap->{$localPort} ) )
        {
            $outBoundCount = $outBoundCount + 1;
            $remoteAddrs->{$remoteAddr} = 1;

            if ( $self->{inspect} == 1 ) {
                my $outBoundStat = $outBoundStats->{$remoteAddr};
                if ( not defined($outBoundStat) ) {
                    $outBoundStat = { SEND_QUEUED_COUNT => 0, SYN_SENT_COUNT => 0 };
                    $outBoundStats->{$remoteAddr} = $outBoundStat;
                }

                if ( $sendQSize > 0 ) {
                    $outBoundStat->{SEND_QUEUED_COUNT} = $outBoundStat->{SEND_QUEUED_COUNT} + 1;
                }
                $outBoundStat->{OUTBOUND_COUNT}   = $outBoundStat->{OUTBOUND_COUNT} + 1;
                $outBoundStat->{SEND_QUEUED_SIZE} = $outBoundStat->{SEND_QUEUED_SIZE} + $sendQSize;
                if ( $connStatus eq 'SYN_SENT' ) {
                    $outBoundStat->{SYN_SENT_COUNT} = $outBoundStat->{SYN_SENT_COUNT} + 1;
                }
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

        if ( $connStatus eq 'SYN_RECV' ) {
            $synRecvCount = $synRecvCount + 1;
        }
        elsif ( $connStatus eq 'CLOSE_WAIT' ) {
            $closeWaitCount = $closeWaitCount + 1;
        }
    }

    print("INFO: Collect process connections complete.\n");

    my $connStatInfo = {
        'TOTAL_COUNT'       => $totalCount,
        'INBOUND_COUNT'     => $inBoundCount,
        'SYN_RECV_COUNT'    => $synRecvCount,
        'CLOSE_WAIT_COUNT'  => $closeWaitCount,
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

    ( $status, $remoteAddrs, $connStatInfo ) = $self->parseConnLines(
        pid         => $pid,
        lsnPortsMap => $lsnPortsMap
    );

    return ( $remoteAddrs, $connStatInfo );
}

sub getListenPorts {
    my ( $self, $pid ) = @_;

    #Linux
    my $status   = 0;
    my $portsMap = {};

    ( $status, $portsMap ) = $self->parseListenLines( pid => $pid );

    return $portsMap;
}

#获取单个进程的连出的TCP/UDP连接
sub getListenInfo {
    my ( $self, $pid ) = @_;
    my $lsnPortsMap = $self->getListenPorts($pid);

    my $connInfo = {};
    $connInfo->{LISTEN} = $lsnPortsMap;

    return $connInfo;
}

sub getStatInfo {
    my ( $self, $pid, $lsnPortsMap ) = @_;
    my ( $remoteAddrs, $connStatInfo ) = $self->getRemoteAddrs( $lsnPortsMap, $pid );

    my $connInfo = {};
    $connInfo->{PEER}  = $remoteAddrs;
    $connInfo->{STATS} = $connStatInfo;

    return $connInfo;
}

#获取连入某进程监听IP端口的远端的IP地址列表
sub getInboundIps {
    my ( $self, $bindAddr, $pid ) = @_;

    my $ipsMap = {};

    my $netstat = $self->{netstat};

    my $procListenTable = $netstat->getProclistenTable($pid);
    foreach my $fields (@$procListenTable) {

        #Proto Recv-Q Send-Q LocalIP localPort           ForeignIP ForeignPort         State       PID
        my $localIp   = $$fields[3];
        my $localPort = $$fields[4];
        my $localAddr = "$localIp:$localPort";

        my $remoteIp   = $$fields[5];
        my $remotePort = $$fields[6];
        my $remoteAddr = "$remoteIp:$remotePort";

        if ( $localAddr =~ /$bindAddr/ and $remoteAddr =~ /^(.*):(\d+)$/ ) {
            #push( @ips, $1 );
            $ipsMap->{$1} = 1;
        }
    }

    my @ips    = keys(%$ipsMap);

    return \@ips;
}
1;
