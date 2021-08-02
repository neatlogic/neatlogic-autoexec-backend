#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package CollectUtils;

use strict;
use IO::File;

sub new {
    my ($type) = @_;
    my $self = {};

    $self->{isRoot} = 0;
    if ( $> == 0 ) {

        #如果EUID是0，那么运行用户就是root
        $self->{isRoot} = 1;
    }

    bless( $self, $type );
    return $self;
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
    if ( $status ne 0 ) {
        print("WARN: execute cmd:$cmd failed.\n");
    }

    return ( $status, $out );
}

#su运行命令，并返回输出的行数组
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
    if ( $status ne 0 ) {
        print("WARN: execute cmd:$cmd failed.\n");
    }

    return ( $status, \@out );
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
        print("WARN: Can not open file:$filePath $!\n");
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
        print("WARN: Can not open file:$filePath $!\n");
    }

    return \@lines;
}

#转换带不确定单位的磁盘空间字串为数值，对应标准单位GB
#譬如：297348 MB：转换为：197.349、 937493 TB：转换为937493000
sub getDiskSizeFormStr {
    my ( $self, $sizeStr ) = @_;
    chomp($sizeStr);
    my $size;
    my $unit = 'GB';
    if ( $sizeStr =~ /K|KB|KiB$/i ) {
        $size = int( $sizeStr / 1000 + 0.5 ) / 1000;
    }
    elsif ( $sizeStr =~ /M|MB|MiB$/i ) {
        $size = int( $sizeStr + 0.5 ) / 1000;
    }
    elsif ( $sizeStr =~ /G|GB|GiB$/i ) {
        $size = $sizeStr + 0.0;
    }
    elsif ( $sizeStr =~ /T|TB|TiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1000;
    }
    elsif ( $sizeStr =~ /P|PB|PiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1000 * 1000;
    }
    elsif ( $sizeStr =~ /\d$/i ) {

        #默认是GB
        $size = $sizeStr + 0.0;
    }
    else {
        $size = $sizeStr;
        $unit = 'unknown';
    }

    return ( $unit, $size );
}

#转换带不确定单位的内存空间字串为数值，对应标准单位MB
#譬如：10240 KB：转换为：10、 10 GB：转换为10240
sub getMemSizeFromStr {
    my ( $self, $sizeStr ) = @_;
    chomp($sizeStr);
    my $size;
    my $unit = 'GB';
    if ( $sizeStr =~ /K|KB|KiB$/i ) {
        $size = int( ( $sizeStr + 0.0 ) / 1024 * 1000 + 0.5 ) / 1000;
    }
    elsif ( $sizeStr =~ /M|MB|MiB$/i ) {
        $size = $sizeStr + 0.0;
    }
    elsif ( $sizeStr =~ /G|GB|GiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1024;
    }
    elsif ( $sizeStr =~ /T|TB|TiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1024 * 1024;
    }
    elsif ( $sizeStr =~ /P|PB|PiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1024 * 1024 * 1024;
    }
    elsif ( $sizeStr =~ /\d$/i ) {

        #默认是MB
        $size = $sizeStr + 0.0;
    }
    else {
        $size = $sizeStr;
        $unit = 'unknown';
    }

    return ( $unit, $size );
}

#转换带不确定单位的网络速度字串为数值，对应标准单位Mb/s
#譬如：297348 Kb/s：转换为：197.349、 937493 Gb/s：转换为937493000
sub getNicSpeedFromStr {
    my ( $self, $speedStr ) = @_;
    chomp($speedStr);
    my $speed;
    my $unit = 'Mb/s';
    if ( $speedStr =~ /K|Kb/i ) {
        $speed = int($speedStr) / 1000;
    }
    elsif ( $speedStr =~ /M|Mb/i ) {
        $speed = $speedStr + 0.0;
    }
    elsif ( $speedStr =~ /G|Gb/i ) {
        $speed = ( $speedStr + 0.0 ) * 1000;
    }
    elsif ( $speedStr =~ /T|Tb/i ) {
        $speed = ( $speedStr + 0.0 ) * 1000 * 1000;
    }
    elsif ( $speedStr =~ /P|Pb/i ) {
        $speed = ( $speedStr + 0.0 ) * 1000 * 1000 * 1000;
    }
    elsif ( $speedStr =~ /\d$/i ) {

        #默认是Kb/s
        $speed = int($speedStr) / 1000;
    }
    else {
        $speed = $speedStr;
        $unit  = 'unknown';
    }

    return ( $unit, $speed );
}

1;
