#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package ConnGather;

use strict;
use POSIX qw(uname);

our $_INSTANCES = {};

sub new {
    my ($type) = @_;

    #实现单态
    my $instance = $_INSTANCES->{$type};

    if ( not defined($instance) ) {
        my @uname  = uname();
        my $osType = $uname[0];
        $osType =~ s/\s.*$//;
        my $gatherClass = "ConnGather$osType";
        print("INFO: Try to use $gatherClass to collect process connection information.\n");
        eval {
            require "$gatherClass.pm";
            our @ISA = ($gatherClass);
            $instance = $gatherClass->new();
        };
        if ($@) {

            #fallback to linux
            print("WARN: Load $gatherClass.pm failed, fallback to ConnGatherBase\n");
            $gatherClass = "ConnGatherBase";
            require "$gatherClass.pm";
            our @ISA = ($gatherClass);
            $instance = $gatherClass->new();
        }
        $_INSTANCES->{$type} = $instance;
    }

    return $instance;
}

1;
