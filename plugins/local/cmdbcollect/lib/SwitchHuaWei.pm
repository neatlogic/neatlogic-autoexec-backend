#!/usr/bin/perl
use strict;

package SwitchHuaWei;

use SwitchBase;
our @ISA = qw(SwitchBase);

sub before {
    my ( $self, $collector ) = @_;
    $collector->addScalarOid( SN => '1.3.6.1.4.1.2011.10.2.6.1.2.1.1.2' );
}

sub after {
    my ( $self, $collector ) = @_;
    my $data = $collector->{DATA};

    my $iosInfo = $data->{IOS_INFO};
    if ( defined($iosInfo) and $iosInfo ne '' ){
        my @iosInfoLines = split(/\n/, $iosInfo);
        $iosInfo = $iosInfoLines[0];
        $iosInfo =~ s/^\s*|\s*$//g;
        $data->{IOS_INFO} = $iosInfo;
    }

    my $model = $data->{MODEL};
    if ( defined($model) ){
        if ( $model =~ /Product Version (.*?)\s*\n/s ){
            $data->{MODEL} = $1;
        }
    }
}

1;
