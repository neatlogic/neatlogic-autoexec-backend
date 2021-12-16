#!/usr/bin/perl
use strict;

package SwitchRuijie;
use SwitchBase;
our @ISA = qw(SwitchBase);

sub before {
    my ($self) = @_;

    #SN可能要调整，如果有多个可能，就在数组里添加
    $self->addScalarOid( SN => [ '1.3.6.1.4.1.9.3.6.3.0', '1.3.6.1.4.1.9.5.1.2.19.0', '1.3.6.1.2.1.47.1.1.1.1.11.1001', '1.3.6.1.2.1.47.1.1.1.1.11.2001', '1.3.6.1.4.1.9.9.92.1.1.1.2.0' ] );
}

sub after {
    my ($self) = @_;
    my $data = $self->{DATA};

    my $iosInfo = $data->{IOS_INFO};
    if ( defined($iosInfo) and $iosInfo ne '' ) {
        $iosInfo =~ s/Switch\s*\(.*$/Switch/is;
        $data->{IOS_INFO} = $iosInfo;
    }

    my $model = $data->{MODEL};
    if ( defined($model) ) {
        if ( $model =~ /Switch\s*\((.*?)\)/is ) {
            $data->{MODEL} = $1;
        }
    }
}

1;

