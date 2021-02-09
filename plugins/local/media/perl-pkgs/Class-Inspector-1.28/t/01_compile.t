#!/usr/bin/perl

# Compile testing for Class::Inspector

use strict;
BEGIN {
	$|  = 1;
	$^W = 1;
}

use Test::More tests => 2;

ok( $] >= 5.006, "Your perl is new enough" );

use_ok('Class::Inspector');
