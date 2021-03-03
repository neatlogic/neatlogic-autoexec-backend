package collection_windows;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;
use Socket;

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();
    my %data = ();
    eval(
        q{
            use Win32::API;
            use Win32;
        }
    );

    #todo windows  collect

    return @collect_data;
}

1;
