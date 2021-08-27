#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/../../lib";

package OSGatherBase;

use strict;
use FindBin;
use Sys::Hostname;
use POSIX qw(:sys_wait_h WNOHANG setsid uname);
use JSON qw(from_json to_json);

use CollectUtils;
use Data::Dumper;

sub new {
    my ($type) = @_;
    my $self = {};

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
        $self->{mgmtIp}     = $nodeInfo->{host};
        $self->{mgmtPort}   = $nodeInfo->{protocolPort};
        #$self->{osId}       = $nodeInfo->{resourceId};
        $self->{resourceid} = $nodeInfo->{resourceId};
    }

    $self->{collectUtils} = CollectUtils->new();

    bless( $self, $type );
    return $self;
}

#su运行命令，并返回输出的文本
sub getCmdOut {
    my ( $self, $cmd, $user ) = @_;
    my $utils = $self->{collectUtils};
    return $utils->getCmdOut( $cmd, $user );
}

#su运行命令，并返回输出的行数组
sub getCmdOutLines {
    my ( $self, $cmd, $user ) = @_;
    my $utils = $self->{collectUtils};
    return $utils->getCmdOutLines( $cmd, $user );
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

sub collect {
    my ($self) = @_;

    my $hostInfo = {};
    my $osInfo   = {};

    my $utils = $self->{collectUtils};

    return ( $hostInfo, $osInfo );
}

1;
