#!/usr/bin/perl
use strict;

package SwitchJuniper;

sub before {
    my ( $self, $collector ) = @_;
    #SN可能要调整，如果有多个可能，就在数组里添加
    $collector->addScalarOid( SN => ['1.3.6.1.4.1.2636.3.40.1.4.1.1.1.2.1'] );
}

1;
