#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package OSGatherBase;

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
    return ( $status, \@out );
}

sub collect {
    my ($self)   = @_;
    my $hostInfo = {};
    my $osInfo   = {};

    return ( $hostInfo, $osInfo );
}

1;
