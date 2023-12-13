#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package OSGather;

use strict;
use POSIX qw(uname);
use OSGatherBase;

our $_INSTANCES = {};

sub new {
    my ( $type, $justBaseInfo, $inspect ) = @_;

    #jusbBaseInfo: 仅仅收集进程计算需要的内存和IP地址信息
    #实现单态
    my $instance = $_INSTANCES->{$type};

    if ( not defined($instance) ) {
        my @uname  = uname();
        my $osType = $uname[0];
        $osType =~ s/\s.*$//;
        my $gatherClass = "OSGather$osType";
        eval {
            require "$gatherClass.pm";
            our @ISA = ($gatherClass);
            $instance = $gatherClass->new( $justBaseInfo, $inspect );
        };
        if ($@) {
            print("ERROR: Load $gatherClass.pm failed, $@\n");
            $instance = OSGatherBase->new( $justBaseInfo, $inspect );
        }
        $_INSTANCES->{$type} = $instance;
    }

    return $instance;
}

1;
