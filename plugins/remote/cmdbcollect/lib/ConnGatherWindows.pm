#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

use strict;

package ConnGatherWindows;

#use parent 'ConnGatherBase';    #继承BASECollector
use ConnGatherBase;
our @ISA = qw(ConnGatherBase);

sub new {
    my ($type) = @_;
    my $self = {};
    bless( $self, $type );
    return $self;
}

sub parseListenLines {
    my ( $self, %args ) = @_;
    print("INFO: Begin to collect process listen addresses.\n");
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
            +$listenAddr =~ s/0000:0000:0000:0000:0000:ffff:(\d+\.)/$1/;

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
        print("INFO: Collect process listen addresses complete.\n");
    }
    else {
        print("ERROR: Can not launch command:$cmd to collect process listen addresses.\n");
    }

    return ( $status, $portsMap );
}

sub parseConnLines {
    my ( $self, %args ) = @_;
    print("INFO: Begin to collect process connections.\n");
    my $cmd            = $args{cmd};
    my $localFieldIdx  = $args{localFieldIdx};
    my $remoteFieldIdx = $args{remoteFieldIdx};
    my $lsnPortsMap    = $args{lsnPortsMap};

    my $totalCount    = 0;
    my $inBoundCount  = 0;
    my $outBoundCount = 0;

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
                    $outBoundCount = $outBoundCount + 1;
                    $remoteAddrs->{$remoteAddr} = 1;
                }
                else {
                    $inBoundCount = $inBoundCount + 1;
                }
                $totalCount = $totalCount + 1;
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

    my $connStatInfo = {
        'TOTAL_COUNT'    => $totalCount,
        'INBOUND_COUNT'  => $inBoundCount,
        'OUTBOUND_COUNT' => $outBoundCount
    };

    return ( $status, $remoteAddrs, $connStatInfo );
}

sub getRemoteAddrs {
    my ( $self, $lsnPortsMap, $pid ) = @_;

    my $cmd            = "netstat -ano| findstr $pid |";
    my $localFieldIdx  = 2;
    my $remoteFieldIdx = 3;
    my ( $status, $remoteAddrs, $connStatInfo ) = $self->parseConnLines(
        cmd            => $cmd,
        lsnPortsMap    => $lsnPortsMap,
        localFieldIdx  => $localFieldIdx,
        remoteFieldIdx => $remoteFieldIdx
    );

    return ( $remoteAddrs, $connStatInfo );
}

sub getListenPorts {
    my ( $self, $pid ) = @_;

    my $cmd         = "netstat -ano| findstr $pid | findstr LISTENING |";
    my $lsnFieldIdx = 2;
    my ( $status, $portsMap ) = $self->parseListenLines(
        cmd         => $cmd,
        lsnFieldIdx => $lsnFieldIdx
    );

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
