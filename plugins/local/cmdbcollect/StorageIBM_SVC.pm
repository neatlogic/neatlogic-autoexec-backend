#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin");
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../pllib/lib/perl5");

package StorageIBM_SVC;
use strict;

use StorageIBM_V7000;
our @ISA = qw(StorageIBM_V7000);

sub collect {
    my ($self) = @_;
    my $data = $self->SUPER::collect();
    $data->{VENDOR} = 'IBM';
    $data->{BRAND}  = 'SVC';

    #修正$data数据
    return $data;
}

1;
