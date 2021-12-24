#!/usr/bin/perl
use strict;
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");

package StorageNetApp;

use StorageBase;
our @ISA = qw(StorageBase);

use JSON;
use Data::Dumper;

sub before {
    my ($self) = @_;
    $self->addScalarOid(
    );

    $self->addTableOid(
    );
}

sub after {
    my ($self) = @_;

    $self->getPools();

    my $data = $self->{DATA};
    #HP_3PAR 8200, ID: 111000, Serial number: 6CU628VY46, InForm OS version: 3.2.2 (MU2)
    my $iosInfo = $data->{IOS_INFO};
    if ( $iosInfo =~ /^(HP_3PAR\s.*?),/ ){
        $data->{MODEL} = $1;
    }
    if ( $iosInfo =~ /Serial\s+number:\s+(.*?),/ ){
        $data->{SN} = $1;
    }
    if ( $iosInfo =~ /OS\s+version:\s+(.*?)$/ or  $iosInfo =~ /OS\s+version:\s+(.*?),/){
        $data->{VERSION} = $1;
    }
    
    $data->{VENDOR} = 'HP_3PAR';
    $data->{BRAND}  = 'HP_3PAR';
    
    return;
}

#get table values from 1 or more than table oid
sub getPools {
    return;
}

1;

