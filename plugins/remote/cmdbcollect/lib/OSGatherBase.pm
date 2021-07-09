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

sub collect {
    my ($self)   = @_;
    my $hostInfo = {};
    my $osInfo   = {};

    return ( $hostInfo, $osInfo );
}

1;
