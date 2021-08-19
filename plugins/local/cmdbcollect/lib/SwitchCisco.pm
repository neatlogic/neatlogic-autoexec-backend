#!/usr/bin/perl
use strict;

package SwitchCisco;
use SwitchBase;
our @ISA = qw(SwitchBase);

sub before {
    my ( $self, $collector ) = @_;
    $collector->addScalarOid( SN => '1.3.6.1.2.1.47.1.1.1.1.11.1' );
}

1;

