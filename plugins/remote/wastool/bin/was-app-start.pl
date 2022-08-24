#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";
#use Data::Dumper;
use Utils;
use CommonConfig;
use Cwd 'abs_path';
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

my $homePath = $FindBin::Bin;
$homePath = abs_path("$homePath/..");
#$ENV{LANG} = 'utf-8';

if ( scalar(@ARGV) != 2 ) {
    my $progName = $FindBin::Script;
    print("ERROR: Use as $progName config-name instance-name\n");
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

my $cmd = "$wasprofile/bin/wsadmin.$shellExt  -lang jython -user $wasUser -password $wasPwd -f $homePath/bin/was-app-poststart.py";
$cmd = "\"$wasprofile/bin/wsadmin.$shellExt\"  -lang jython -user $wasUser -password $wasPwd -f \"$homePath/bin/was-app-poststart.py\""
    if ( $ostype eq 'windows' );
if ( not defined($wasPwd) or $wasPwd eq '' ) {
    $cmd = "$wasprofile/bin/wsadmin.$shellExt  -lang jython -f $homePath/bin/was-app-poststart.py";
    $cmd = "\"$wasprofile/bin/wsadmin.$shellExt\"  -lang jython -f \"$homePath/bin/was-app-poststart.py\"" if ( $ostype eq 'windows' );
}
$ENV{'TS_WASDEPLOYTOOL_HOME'} = $homePath;
$ENV{'TS_WASCONF_NAME'}       = $confName;
$ENV{'TS_WASINS_NAME'}        = $insName;

#system($cmd);
Utils::execCmd($cmd);

