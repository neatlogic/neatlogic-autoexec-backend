#!/usr/bin/perl
use strict;

package SwitchH3C;
use SwitchBase;
our @ISA = qw(SwitchBase);

sub before {
    my ($self) = @_;

    #SN可能要调整，如果有多个可能，就在数组里添加
    $self->addScalarOid( SN => ['1.3.6.1.2.1.47.1.1.1.1.11.1','1.3.6.1.2.1.47.1.1.1.1.11.2','1.3.6.1.2.1.47.1.1.1.1.11.19'] );
}

1;

