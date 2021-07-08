#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

use strict;

package OSGatherWindows;

use OSGatherBase;
our @ISA = qw(OSGatherBase);

sub collect{
    my ($self) = @_;
}

1;
