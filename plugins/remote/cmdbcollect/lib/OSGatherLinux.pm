#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

use strict;

package OSGatherLinux;

use OSGatherBase;
our @ISA = qw(OSGatherBase);

sub collect{
    my ($self) = @_;
    my $hostInfo = {};
    my $osInfo = {};

    return ($hostInfo, $osInfo);
}

1;
