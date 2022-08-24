#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";
#use Data::Dumper;
use Utils;
use POSIX qw(uname);

my @uname    = uname();
my $ostype   = $uname[0];
my $shellExt = 'sh';
my $nullDev  = '/dev/null';

if ( $ostype =~ /Windows/i ) {
    $ostype   = 'windows';
    $shellExt = 'bat';
    $nullDev  = 'NUL';
}
else {
    $ostype   = 'unix';
    $shellExt = 'sh';
    $nullDev  = '/dev/null';
}

use CommonConfig;
use Cwd 'abs_path';
my $homePath = $FindBin::Bin;
$homePath = abs_path("$homePath/..");
$ENV{LANG} = 'utf-8';

if ( scalar(@ARGV) != 2 ) {
    my $progName = $FindBin::Script;
    print("ERROR: Use as $progName config-name\n");
    exit(1);
}

chdir($homePath);
my $configName = $ARGV[0];
my $insName    = $ARGV[1];
my $insPrefix  = $insName;
$insPrefix =~ s/\d*$//;

my $sectionConfig;
my $config = CommonConfig->new( "$homePath/conf", "wastool.ini" );
$sectionConfig = $config->getConfig("$configName.$insName");
my $confName = "$configName.$insName";
if ( not defined($sectionConfig) ) {
    $sectionConfig = $config->getConfig("$configName.$insPrefix");
    $confName      = "$configName.$insPrefix";
}
if ( not defined($sectionConfig) ) {
    $confName      = $configName;
    $sectionConfig = $config->getConfig("$configName");
}
my $wasprofile = $sectionConfig->{"was_profile"};
my $wasUser    = $sectionConfig->{"was_user"};
my $wasPwd     = $sectionConfig->{"was_pwd"};

if ( defined($wasprofile) and $wasprofile ne '' and -d $wasprofile ) {
    my $cmd;
    if ( $ostype eq 'windows' ) {
        $cmd = "\"$wasprofile/bin/stopNode.$shellExt\"  -user $wasUser  -password $wasPwd";
    }
    else {
        $cmd = "$wasprofile/bin/stopNode.$shellExt  -user $wasUser  -password $wasPwd";
    }

    #my $cmd = "$wasprofile/bin/stopNode.sh  -user $wasUser  -password $wasPwd";
    if ( not defined($wasPwd) or $wasPwd eq '' ) {
        $cmd = "$wasprofile/bin/stopNode.$shellExt"     if ( $ostype eq 'windows' );
        $cmd = "\"$wasprofile/bin/stopNode.$shellExt\"" if ( $ostype ne 'windows' );
    }

    #system($cmd);
    Utils::execCmd($cmd);
}

