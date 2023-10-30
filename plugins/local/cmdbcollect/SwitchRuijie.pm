#!/usr/bin/perl
use strict;

package SwitchRuijie;
use SwitchBase;
our @ISA = qw(SwitchBase);

sub before {
    my ($self) = @_;

    #SN可能要调整，如果有多个可能，就在数组里添加
    $self->addScalarOid(
        SN       => [ '1.3.6.1.4.1.4881.1.1.10.2.21.1.2.1.10.1', '1.3.6.1.4.1.4881.1.1.10.2.1.1.24.0' ],
        IOS_INFO => '1.3.6.1.4.1.4881.1.1.10.2.21.1.2.1.8.1',
        MODEL    => '1.3.6.1.4.1.4881.1.1.10.2.21.1.2.1.2.1'
    );
}

sub after {
    my ($self) = @_;
    my $data = $self->{DATA};
}

1;

