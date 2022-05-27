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
    print("ERROR:use as $progName config-name instance-name\n");
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

my $wasprofile = $sectionConfig->{was_profile};
my $cellname   = $sectionConfig->{cellname};
my $appname    = $sectionConfig->{appname};
my $was_user   = $sectionConfig->{was_user};
my $was_pwd    = $sectionConfig->{was_pwd};
my $appfile    = $sectionConfig->{appfile};

my $ihs_dir     = $sectionConfig->{ihs_dir};
my $ihs_docroot = $sectionConfig->{ihs_docroot};

my @appnames;
if ( defined($appname) and $appname ne '' ) {
    @appnames = split( /\s*,\s*/, $appname );
}

my @appfiles;
if ( defined($appfile) and $appfile ne '' ) {
    @appfiles = split( /\s*,\s*/, $appfile );
}

if ( defined($appname) and defined($appfile) ) {
    if ( scalar(@appfiles) != scalar(@appnames) ) {
        print('appfiles#####');
        print( $appfile, "\n" );
        print('appnames#####');
        print( $appname, "\n" );
        print('ERROR: config item:appname and appfile count not match.\n');
    }
}

if ( ( not defined($appname) and defined($appfile) ) or ( not defined($appname) and not defined($appfile) ) ) {
    print('ERROR: appname and appfile must mapping correct.\n');
}

my $isFirstDeploy = 1;

my $celldir = "$wasprofile/installedApps/$cellname";
if ( -d $celldir ) {
    print("SUCCESS: WAS cell dir check OK, $celldir exists.\n");
}
else {
    print("ERROR: WAS cell dir $celldir not exists, check config item:wasprofile and cellname.\n");
}

if ( defined($ihs_docroot) and $ihs_docroot ne '' ) {
    if ( -d $ihs_docroot ) {
        print("SUCCESS: IHS doc root check OK, $ihs_docroot exists.\n");
    }
    else {
        print("ERROR: IHS doc root $ihs_docroot not exists. check config item:ihs_docroot.\n");
    }

    if ( -d $ihs_dir ) {
        print("SUCCESS: IHS dir check OK, $ihs_dir exists.\n");
    }
    else {
        print("ERROR: IHS dir $ihs_dir not exists. check config item:ihs_dir.\n");
    }
}

my $i = 0;
if ( defined($appname) and defined($appfile) ) {
    foreach $appname (@appnames) {
        $appfile = $appfiles[$i];
        $i       = $i + 1;
        if ( index( $appfile, '.war' ) > 0 ) {
            my $targetdir = "$wasprofile/installedApps/$cellname/$appname.ear/$appfile";
            if ( -d $targetdir ) {
                print("SUCCESS: WAS app dir check OK, $targetdir exists.\n");
            }
        }

        elsif ( index( $appfile, '.ear' ) > 0 ) {
            my $targetdir = "$wasprofile/installedApps/$cellname/$appname";
            if ( -d $targetdir ) {
                print("SUCCESS: WAS app dir check OK, $targetdir exists.\n");
            }
        }
    }
}

if ( $isFirstDeploy == 1 and defined($wasprofile) and $wasprofile ne '' ) {
    my $cmd = "$wasprofile/bin/wsadmin.$shellExt  -lang jython -user $was_user -password $was_pwd -f $homePath/bin/was-postcheck.py";
    $cmd = "\"$wasprofile/bin/wsadmin.$shellExt\"  -lang jython -user $was_user -password $was_pwd -f \"$homePath/bin/was-postcheck.py\""
        if ( $ostype eq 'windows' );
    if ( not defined($was_pwd) or $was_pwd eq '' ) {
        $cmd = "$wasprofile/bin/wsadmin.$shellExt  -lang jython -f $homePath/bin/was-postcheck.py";
        $cmd = "\"$wasprofile/bin/wsadmin.$shellExt\"  -lang jython -f \"$homePath/bin/was-postcheck.py\"" if ( $ostype eq 'windows' );
    }

    $ENV{'TS_WASDEPLOYTOOL_HOME'} = $homePath;
    $ENV{'TS_WASCONF_NAME'}       = $confName;
    $ENV{'TS_WASINS_NAME'}        = $insName;

    #system($cmd);
    Utils::execCmd($cmd);
}
