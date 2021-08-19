#!/usr/bin/perl
use strict;

package SwitchH3C;

sub before {
    my ( $self, $collector ) = @_;
    $collector->addScalarOid( SN => '1.3.6.1.4.1.25506.2.6.1.2.1.1.2' );
}

1;

