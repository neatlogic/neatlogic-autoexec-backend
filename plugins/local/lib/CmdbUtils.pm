#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

package CmdbUtils;

use strict;
use utf8;
use MongodbRunner;

sub new {
    my ($type)   = @_;
    my $dbRunner = new MongodbRunner();
    my $self     = { dbRunner => $dbRunner };
    return bless( $self, $type );
}

sub saveCollectData {
    my ( $self, %args ) = @_;
    my $dbRunner   = $self->{dbRunner};
    my $table      = $args{table};
    my @uniqueName = $args{uniqueName};
    my $data       = $args{data};

    my $isSuccess;
    my $filter;
    if ( scalar(@uniqueName) gt 0 ) {
        $filter = { '$and' => @uniqueName };
    }
    else {
        $filter = {};
    }

    my $count = $dbRunner->count( table => $table, filter => $filter );
    if ( $count == 0 ) {
        $isSuccess = $dbRunner->insert( table => $table, data => $data );
    }
    else {
        $isSuccess = $dbRunner->update( table => $table, filter => $filter, data => $data );
    }
    $dbRunner->close();
    if ( $isSuccess == 0 ) {
        print("INFO: $table save success.\n");
    }
    else {
        print("ERROR: $table save failed.\n");
    }
    return $isSuccess;
}

1;
