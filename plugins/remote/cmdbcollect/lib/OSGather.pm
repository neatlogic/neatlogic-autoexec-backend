#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package OSGather;

use strict;
use POSIX qw(uname);
use OSGatherBase;

our $_INSTANCES = {};

sub new {
    my ($type) = @_;

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
            $instance = $gatherClass->new();
        };
        if ($@) {
            print("ERROR: Load $gatherClass.pm failed, $@\n");
            $instance = OSGatherBase->new();
        }
        $_INSTANCES->{$type} = $instance;
    }

    return $instance;
}

1;
