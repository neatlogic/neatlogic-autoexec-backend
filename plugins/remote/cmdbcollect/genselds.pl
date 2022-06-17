#!/usr/bin/perl
use strict;
use JSON;
use FindBin;

sub main() {
    my $collectorDir = $FindBin::Bin;
    my $prefixLen    = length($collectorDir);

    my @dataList = ();

    for my $collector ( glob("$collectorDir/*Collector.pm") ) {
        my $collectorName = substr( $collector, $prefixLen + 1, length($collector) - $prefixLen - 13 );

        if ( $collectorName ne 'Demo' ) {
            print( $collectorName, "\n" );
            my $fieldInfo = {
                text  => $collectorName,
                value => $collectorName
            };
            push( @dataList, $fieldInfo );
        }
    }

    @dataList = sort { lc($a) cmp lc($b) } @dataList;

    unshift(
        @dataList,
        {
            text  => "OS",
            value => "OS"
        }
    );
    unshift(
        @dataList,
        {
            text  => "ALL",
            value => ""
        }
    );
    print( to_json( \@dataList, { pretty => 1 } ) );
}

exit main();
