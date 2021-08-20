#!/usr/bin/perl
use strict;

package SwitchCisco;
use SwitchBase;
our @ISA = qw(SwitchBase);

sub before {
    my ( $self, $collector ) = @_;
    #SN可能要调整，如果有多个可能，就在数组里添加
    $collector->addScalarOid( SN => ['1.3.6.1.2.1.47.1.1.1.1.11.1'] );
}

sub after {
    my ( $self, $collector ) = @_;
    my $data = $collector->{DATA};

    my $iosInfo = $data->{IOS_INFO};
    if ( defined($iosInfo) and $iosInfo ne '' ){
        $iosInfo =~ s/, RELEASE SOFTWARE//is;
        $data->{IOS_INFO} = $iosInfo;
    }

    my $model = $data->{MODEL};
    if ( defined($model) ){
        if ( $model =~ /Cisco (.*?),/s ){
            $data->{MODEL} = $1;
        }
    }
}

1;

