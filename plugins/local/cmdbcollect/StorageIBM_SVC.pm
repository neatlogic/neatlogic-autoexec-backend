#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");

package StorageIBM_SVC;
use strict;

use StorageIBM_V7000;
our @ISA = qw(StorageIBM_V7000);


sub collect {
    my ($self) = @_;
    my $data = $self->SUPER::collect();

    #修正$data数据
    return $data;
}

1;
