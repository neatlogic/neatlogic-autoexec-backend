#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../pllib/lib/perl5");

use Net::OpenSSH;
use JSON;
use CollectUtils;

package StorageIBM_Flash;
use strict;

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

