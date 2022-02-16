#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/../../lib";

package OSGatherBase;

use strict;
use FindBin;
use Sys::Hostname;
use Net::Netmask;
use POSIX qw(:sys_wait_h WNOHANG setsid uname);
use JSON qw(from_json to_json);

use CollectUtils;

sub new {
    my ( $type, $justBaseInfo, $inspect ) = @_;

    #jusbBaseInfo: 仅仅收集进程计算需要的内存和IP地址信息

    my $self = {};
    $self->{justBaseInfo} = $justBaseInfo;
    $self->{inspect}      = $inspect;
    $self->{verbose}      = 0;
    my @uname  = uname();
    my $ostype = $uname[0];
    $ostype =~ s/\s.*$//;
    $self->{ostype}   = $ostype;
    $self->{hostname} = hostname();

    $self->{osId}     = '';
    $self->{mgmtIp}   = '';    #此主机节点Agent或ssh连接到此主机，主机节点端的IP
    $self->{mgmtPort} = '';    #此主机节点Agent或ssh连接到此主机，主机节点端的port
    my $AUTOEXEC_NODE = $ENV{'AUTOEXEC_NODE'};

    if ( defined($AUTOEXEC_NODE) and $AUTOEXEC_NODE ne '' ) {
        my $nodeInfo = from_json($AUTOEXEC_NODE);
        $self->{mgmtIp}   = $nodeInfo->{host};
        $self->{mgmtPort} = $nodeInfo->{protocolPort};
        $self->{osId}     = $nodeInfo->{resourceId};
    }

    $self->{collectUtils} = CollectUtils->new();

    bless( $self, $type );
    return $self;
}

#su运行命令，并返回输出的文本
sub getCmdOut {
    my ( $self, $cmd, $user, $opts ) = @_;
    my $utils = $self->{collectUtils};
    if ( not defined($opts) ) {
        $opts = {};
    }
    $opts->{verbose} = $self->{verbose};
    return $utils->getCmdOut( $cmd, $user, $opts );
}

#su运行命令，并返回输出的行数组
sub getCmdOutLines {
    my ( $self, $cmd, $user, $opts ) = @_;
    my $utils = $self->{collectUtils};
    if ( not defined($opts) ) {
        $opts = {};
    }
    $opts->{verbose} = $self->{verbose};
    return $utils->getCmdOutLines( $cmd, $user, $opts );
}

sub getFileContent {
    my ( $self, $filePath ) = @_;
    my $utils = $self->{collectUtils};
    return $utils->getFileContent($filePath);
}

#读取文件所有行
sub getFileLines {
    my ( $self, $filePath ) = @_;
    my $utils = $self->{collectUtils};
    return $utils->getFileLines($filePath);
}

sub getBizIp {
    my ( $self, $ipAddrs, $ipv6Addrs ) = @_;

    #预留用于计算管理IP和业务IP不一致的情况的主机IP
    return $self->{mgmtIp};
}

sub collect {
    my ($self) = @_;

    my $hostInfo = {};
    my $osInfo   = {};

    my $utils = $self->{collectUtils};

    return ( $hostInfo, $osInfo );
}

1;
