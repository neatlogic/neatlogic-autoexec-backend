#!/usr/bin/perl
use strict;
use FindBin;

my $binPath = "/opt/python/autoexec/tools/stonavm";
$ENV{'LIBPATH'} = "$binPath:\$LIBPATH";
$ENV{'SHLIB_PATH'} = "$binPath/lib:\$SHLIB_PATH";
$ENV{'LD_LIBRARY_PATH'} = "$binPath/lib:\$LD_LIBRARY_PATH";
$ENV{'STONAVM_HOME'} = "$binPath";
$ENV{'STONAVM_ACT'} = 'on';
$ENV{'STONAVM_RSP_PASS'} = 'on';
$ENV{'PATH'} = "\$PATH:$binPath";

print(" $binPath/auunitinfo -h ");
my $rs = `$binPath/auunitinfo -h`;
print $rs ;



my @array = ('11', '22', '33', '44','55');
# The position of first "ray" is 0
#splice (@array, 0, 1);
#print "Now array is @array\n";
# The position of first "ray" is 2

splice (@array, 0,2);
print " @array\n"
