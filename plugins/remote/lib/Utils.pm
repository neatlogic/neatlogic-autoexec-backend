#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;

package Utils;

use IO::File;
use JSON qw(to_json from_json);


sub saveOutput {
    my ($outputData) = @_;
    my $outputPath = "$FindBin::Bin/output.json";

    if ( defined($outputPath) and $outputPath ne '' ) {
        my $fh = IO::File->new(">$outputPath");
        if ( defined($fh) ) {
            print $fh ( to_json($outputData) );
            $fh->close();
        }
        else {
            die("ERROR: Can not open output file:$outputPath to write.\n");
        }
    }
}

1;

