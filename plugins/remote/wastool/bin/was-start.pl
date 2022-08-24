#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";
#use Data::Dumper;
use Utils;
use POSIX qw(uname);

my $rc = 0;

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

if ( scalar(@ARGV) < 2 ) {
    my $progName = $FindBin::Script;
    print("ERROR: Use as $progName config-name instance-name\n");
    exit(1);
}

chdir($homePath);
my $configName = $ARGV[0];
my $insName    = $ARGV[1];

if ( scalar(@ARGV) > 2 ) {
    my $argsLen = scalar(@ARGV);
    my $i;
    for ( $i = 2 ; $i < $argsLen ; $i++ ) {
        my $envLine = $ARGV[$i];
        if ( $envLine =~ /\s*(\w+)\s*=\s*(.*)\s*$/ ) {
            $ENV{$1} = $2;
        }
    }
}

my $insPrefix = $insName;
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

my $umask = $sectionConfig->{"umask"};
if ( defined($umask) and $umask ne '' ) {
    umask($umask);
}

my $lang  = $sectionConfig->{"lang"};
my $lcAll = $sectionConfig->{"lc_all"};
$ENV{LANG}   = $lang  if ( defined($lang)  and $lang ne '' );
$ENV{LC_ALL} = $lcAll if ( defined($lcAll) and $lcAll ne '' );

my $wasprofile = $sectionConfig->{"was_profile"};
my $cellname   = $sectionConfig->{"cellname"};
my $wasUser    = $sectionConfig->{"was_user"};
my $wasPwd     = $sectionConfig->{"was_pwd"};

my $ihsDir = $sectionConfig->{"ihs_dir"};

my $startTimeout = $sectionConfig->{'start_timeout'};
if ( not defined($startTimeout) or $startTimeout eq '' ) {
    $startTimeout = 300;
}

#print("debug $needDeploy,$wasprofile,$cellname,$appfile,$appname,$wasUser,$wasPwd\n");

my $appnames = $sectionConfig->{"appname"};
$appnames =~ s/\s*//g;
my @appNames = split( ",", $appnames );

my $appfiles = $sectionConfig->{"appfile"};
$appfiles =~ s/\s*//g;
my @appFiles = split( ",", $appfiles );

my $servernames = $sectionConfig->{"servername"};
$servernames =~ s/\s*//g;
my @serverNames = split( ",", $servernames );

if ( scalar(@appNames) != scalar(@appFiles) ) {
    print("ERROR: Config error, appfile number is not same as appname number.\n");
    exit(1);
}

my $timeout = int($startTimeout);

if ( defined($wasprofile) and $wasprofile ne '' and defined($servernames) and $servernames ne '' ) {
    foreach my $appname (@appNames) {
        my $precheckUrl = $sectionConfig->{"$appname.precheckurl"};
        if ( defined($precheckUrl) and $precheckUrl ne '' ) {
            if ( not Utils::CheckUrlAvailable( $precheckUrl, "GET", $timeout ) ) {
                print("ERROR: Pre-check url $precheckUrl is not available in $timeout s, starting halt.\n");
                exit(1);
            }
        }
    }

    my @serverLogInfos;
    foreach my $servername (@serverNames) {
        my $logFile = "$wasprofile/logs/$servername/SystemOut.log";
        my $logInfo = {};
        $logInfo->{server} = $servername;
        $logInfo->{path}   = $logFile;
        $logInfo->{pos}    = undef;
        my $fh = IO::File->new("<$logFile");
        if ( defined($fh) ) {
            $fh->seek( 0, 2 );
            $logInfo->{pos} = $fh->tell();
            $fh->close();
        }

        push( @serverLogInfos, $logInfo );
    }

    foreach my $servername (@serverNames) {
        my $cmd = "$wasprofile/bin/startServer.$shellExt $servername";
        $cmd = "\"$wasprofile/bin/startServer.$shellExt\" $servername" if ( $ostype eq 'windows' );

        #system($cmd);
        Utils::execCmd($cmd);
    }

    foreach my $appname (@appNames) {
        my $checkUrl = $sectionConfig->{"$appname.checkurl"};
        if ( defined($checkUrl) and $checkUrl ne '' ) {
            if ( Utils::CheckUrlAvailable( $checkUrl, "GET", $timeout, \@serverLogInfos ) ) {
                print("INFO: App $appname started.\n");
            }
            else {
                print("ERROR: App $appname start failed.\n");
                $rc = 2;
            }
        }
    }
}

if ( defined($ihsDir) and $ihsDir ne '' and -d $ihsDir ) {
    my $cmd = "$ihsDir/bin/apachectl start";
    $cmd = "\"$ihsDir/bin/apachectl start\"" if ( $ostype eq 'windows' );

    #system($cmd);
    Utils::execCmd($cmd);
}

exit($rc);
