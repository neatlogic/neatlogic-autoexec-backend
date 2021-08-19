#!/usr/bin/perl
use strict;

package SwitchHuaWei;

use SwitchBase;
our @ISA = qw(SwitchBase);

sub before {
    my ( $self, $collector ) = @_;
    $collector->addScalarOid( SN => '1.3.6.1.4.1.2011.10.2.6.1.2.1.1.2' );
}

1;

