#!/usr/bin/perl
use strict;

package SwitchH3C;

sub before {
    my ( $self, $collector ) = @_;
    #SN可能要调整，如果有多个可能，就在数组里添加
    $collector->addScalarOid( SN => ['1.3.6.1.2.1.47.1.1.1.1.11.2']);
}

1;

