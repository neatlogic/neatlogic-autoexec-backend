#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;

package Utils;

use IO::File;
use JSON qw(to_json from_json encode_json);

sub setEnv {
    $ENV{OUTPUT_PATH} = 'output.json';
}

sub saveOutput {
    my ($outputData) = @_;
    my $outputPath = $ENV{OUTPUT_PATH};

    if ( defined($outputPath) and $outputPath ne '' ) {
        my $fh = IO::File->new(">$outputPath");
        if ( defined($fh) ) {
            print $fh ( encode_json($outputData) );
            $fh->close();
        }
        else {
            die("ERROR: Can not open output file:$outputPath to write.\n");
        }
    }
}

sub getNode {
    my ($nodeId) = @_;
    my $nodesJsonPath = $ENV{TASK_NODES_PATH};

    my $node = {};
    my $fh   = IO::File->new("<$nodesJsonPath");
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            my $cNode = from_json($line);
            if ( $cNode->{nodeId} == $nodeId ) {
                $node = $cNode;
                last;
            }
        }
        $fh->close();
    }

    return $node;
}

sub getNodes {
    my $nodesJsonPath = $ENV{TASK_NODES_PATH};

    my $nodesMap = {};
    my $fh       = IO::File->new("<$nodesJsonPath");
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            my $node = from_json($line);
            $nodesMap->{ $node->{nodeId} } = $node;
        }
        $fh->close();
    }

    return $nodesMap;
}

1;

