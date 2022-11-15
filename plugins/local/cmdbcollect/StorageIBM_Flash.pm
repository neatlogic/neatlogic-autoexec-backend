#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../plib/lib/perl5";

use strict;

package StorageIBM_Flash;

use Net::OpenSSH;
use JSON;
use CollectUtils;
use StorageIBM_V7000;

our @ISA = qw(StorageIBM_V7000);

sub collect {
    my ($self) = @_;
    my $data = $self->SUPER::collect();

    $data->{VENDOR} = 'IBM';
    $data->{BRAND}  = 'Flash';

    #修正$data数据
    return $data;
}

1;

