#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/../../lib";

package OSGatherBase;

use strict;
use FindBin;
use POSIX qw(:sys_wait_h WNOHANG setsid uname);
use Sys::Hostname;
use Data::Dumper;

sub new {
    my ($type) = @_;
    my $self = {};

    my @uname  = uname();
    my $ostype = $uname[0];
    $self->{ostype}   = $ostype;
    $self->{hostname} = hostname();

    $self->{osId}        = '';
    $self->{mgmtIp}   = '';    #此主机节点Agent或ssh连接到此主机，主机节点端的IP
    $self->{mgmtPort} = '';    #此主机节点Agent或ssh连接到此主机，主机节点端的port
    my $AUTOEXEC_NODE = $ENV{'AUTOEXEC_NODE'};

    if ( defined $AUTOEXEC_NODE and $AUTOEXEC_NODE ne '' ) {
        my $nodeInfo = from_json($AUTOEXEC_NODE);
        $self->{mgmtIp}   = $nodeInfo->{host};
        $self->{mgmtPort} = $nodeInfo->{mgmtPort};
        $self->{osId}        = $nodeInfo->{osId};
    }

    bless( $self, $type );
    return $self;
}

sub getFileContent {
    my ( $self, $filePath ) = @_;
    my $fh = IO::File->new( $filePath, 'r' );
    my $content;
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            $content = $content . $line;
        }
        $fh->close();
    }
    else {
        print("ERROR: Can not open file:$filePath $!\n");
    }

    return $content;
}

#读取文件所有行
sub getFileLines {
    my ( $self, $filePath ) = @_;
    my @lines;
    my $fh = IO::File->new( $filePath, 'r' );
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            push( @lines, $line );
        }
        $fh->close();
    }
    else {
        print("ERROR: Can not open file:$filePath $!\n");
    }

    return \@lines;
}

#su运行命令，并返回输出的文本
sub getCmdOut {
    my ( $self, $cmd, $user ) = @_;
    my $out = '';
    if ( defined($user) ) {
        if ( $self->{isRoot} ) {
            $out = `su - '$user' -c '$cmd'`;
        }
        elsif ( getpwnam($user) == $> ) {

            #如果运行目标用户是当前用户，$>:EFFECTIVE_USER_ID
            $out = `$cmd`;
        }
        else {
            print("WARN: Can not execute cmd:$cmd by user $user.\n");
        }
    }
    else {
        $out = `$cmd`;
    }

    my $status = $?;
    if ( $status ne 0 ){
        print("ERROR: execute cmd:$cmd failed.\n");
    }

    return ( $status, $out );
}

#su运行命令，并返回输出的数组
sub getCmdOutLines {
    my ( $self, $cmd, $user ) = @_;
    my @out = ();
    if ( defined($user) ) {
        if ( $self->{isRoot} ) {
            @out = `su - '$user' -c '$cmd'`;
        }
        elsif ( getpwnam($user) == $> ) {

            #如果运行目标用户是当前用户，$>:EFFECTIVE_USER_ID
            @out = `$cmd`;
        }
        else {
            print("WARN: Can not execute cmd:$cmd by user $user.\n");
        }
    }
    else {
        @out = `$cmd`;
    }

    my $status = $?;
    if ( $status ne 0 ){
        print("ERROR: execute cmd:$cmd failed.\n");
    }
    
    return ( $status, \@out );
}

sub collect {
    my ($self)   = @_;
    my $hostInfo = {};
    my $osInfo   = {};

    return ( $hostInfo, $osInfo );
}

1;
