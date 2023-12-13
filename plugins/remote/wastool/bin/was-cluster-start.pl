#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";
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

my $umask = $sectionConfig->{"umask"};
if ( defined($umask) and $umask ne '' ) {
    umask($umask);
}

my $startTimeout = $sectionConfig->{'start_timeout'};
if ( not defined($startTimeout) or $startTimeout eq '' ) {
    $startTimeout = 300;
}

my $timeout = int($startTimeout);

my $appName = $sectionConfig->{"appname"};
$appName =~ s/\s*//g;
my @appNames = split( ",", $appName );

foreach $appName (@appNames) {
    my $checkUrl = $sectionConfig->{"$appName.precheckurl"};
    if ( defined($checkUrl) and $checkUrl ne '' ) {
        if ( not Utils::CheckUrlAvailable( $checkUrl, "GET", $timeout ) ) {
            print("ERROR: Pre-check url $checkUrl is not available in $timeout s, starting halt.\n");
            exit(1);
        }
    }
}

my $cmd = "$wasprofile/bin/wsadmin.$shellExt  -lang jython -user $wasUser -password $wasPwd -f $homePath/bin/was-cluster-poststart.py";
$cmd = "\"$wasprofile/bin/wsadmin.$shellExt\"  -lang jython -user $wasUser -password $wasPwd -f \"$homePath/bin/was-cluster-poststart.py\""
    if ( $ostype eq 'windows' );
if ( not defined($wasPwd) or $wasPwd eq '' ) {
    $cmd = "$wasprofile/bin/wsadmin.sh  -lang jython -f $homePath/bin/was-cluster-poststart.py";
    $cmd = "\"$wasprofile/bin/wsadmin.sh\"  -lang jython -f \"$homePath/bin/was-cluster-poststart.py\"" if ( $ostype eq 'windows' );
}
$ENV{'TS_WASDEPLOYTOOL_HOME'} = $homePath;
$ENV{'TS_WASCONF_NAME'}       = $confName;
$ENV{'TS_WASINS_NAME'}        = $insName;

#system($cmd);
Utils::execCmd($cmd);

foreach $appName (@appNames) {
    my $checkUrl = $sectionConfig->{"$appName.checkurl"};
    if ( defined($checkUrl) and $checkUrl ne '' ) {
        if ( not Utils::CheckUrlAvailable( $checkUrl, "GET", $timeout ) ) {
            print("ERROR: Check url $checkUrl is not available in $timeout s, starting halt.\n");
            exit(1);
        }
    }
}
