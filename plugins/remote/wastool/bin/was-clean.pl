#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

#use Data::Dumper;
use CommonConfig;
use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Path;
use Cwd;
use Utils;
use POSIX qw(uname);

my $rc = 0;

my @uname    = uname();
my $ostype   = $uname[0];
my $shellExt = 'sh';
my $nullDev  = '/dev/null';

if ( $ostype =~ /Windows/i ) {
    $ostype   = 'windows';
    $shellExt = 'cmd';
    $nullDev  = 'NUL';
}
else {
    $ostype   = 'unix';
    $shellExt = 'sh';
    $nullDev  = '/dev/null';
}

my $homePath = $FindBin::Bin;
$homePath = abs_path("$homePath/..");
$ENV{LANG} = 'utf-8';

if ( scalar(@ARGV) != 2 ) {
    my $progName = $FindBin::Script;
    print("ERROR:use as $progName config-name instance-name\n");
    exit(1);
}

chdir($homePath);
my $mainName   = $ARGV[0];
my $configName = $mainName;
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

my $lang  = $sectionConfig->{"lang"};
my $lcAll = $sectionConfig->{"lc_all"};
$ENV{LANG}   = $lang  if ( defined($lang)  and $lang ne '' );
$ENV{LC_ALL} = $lcAll if ( defined($lcAll) and $lcAll ne '' );

my $dmgrprofile = $sectionConfig->{"dmgr_profile"};
my $standalone  = $sectionConfig->{"standalone"};
my $wasprofile  = $sectionConfig->{"was_profile"};
my $cellname    = $sectionConfig->{"cellname"};
my $nodename    = $sectionConfig->{"nodename"};
my $wasUser     = $sectionConfig->{"was_user"};
my $wasPwd      = $sectionConfig->{"was_pwd"};
my $needDeploy  = $sectionConfig->{"need_deploy"};

$ENV{WAS_PROFILE_PATH} = $wasprofile;

if ( not defined($needDeploy) or $needDeploy =~ /[1|true]/i ) {
    $needDeploy = 1;
}
else {
    $needDeploy = 0;
}

my $ihsRoot = $sectionConfig->{"ihs_docroot"};

my $servername = $sectionConfig->{"servername"};
$servername =~ s/\s*//g;
my @serverNames = split( ",", $servername );

my $appName = $sectionConfig->{"appname"};
$appName =~ s/\s*//g;
my @appNames = split( ",", $appName );

my $appFile = $sectionConfig->{"appfile"};
$appFile =~ s/\s*//g;
my @appFiles = split( ",", $appFile );

if ( scalar(@appNames) != scalar(@appFiles) ) {
    print("ERROR: config error, appfile number is not same as appname number.\n");
    exit(1);
}

my $pkgsDir = $sectionConfig->{"pkgs_dir"};
if ( not defined($pkgsDir) or $pkgsDir eq '' ) {
    $pkgsDir = "$homePath/pkgs";
}

my $isFirstDeploy = 1;
if ( $needDeploy == 1 ) {
    my $appNum = scalar(@appNames);
    for ( my $i = 0 ; $i < $appNum ; $i++ ) {
        my $appName = $appNames[$i];
        my $appFile = $appFiles[$i];

        my $appfilePath;
        if ( -e $appFile or $appFile =~ /^[\/\\]/ ) {
            $appfilePath = $appFile;
            $appFile     = basename($appFile);
        }
        else {
            $appfilePath = "$pkgsDir/$insName/$appFile";
        }

        my $targetDir = '';
        if ( $appFile =~ /\.war$/ ) {

            my $descTarget = "$wasprofile/config/cells/$cellname/applications/$appName.ear/deployments/$appName";
            my $dmgrTarget = "$dmgrprofile/config/cells/$cellname/applications/$appName.ear/deployments/$appName";

            my $appDir = $sectionConfig->{"$appName.targetdir"};
            if ( defined($appDir) and $appDir ne '' ) {
                $targetDir = "$appDir/$appName.ear/$appFile";
            }
            else {
                $targetDir = "$wasprofile/installedApps/$cellname/$appName.ear/$appFile";
            }

            if ( -d $targetDir and -d $descTarget ) {
                $isFirstDeploy = 0;
                foreach my $serverName (@serverNames) {
                    my $tmpDir = "$wasprofile/temp/$nodename/$serverName/$appName";
                    if ( -e $tmpDir ) {

                        #system("rm -rf $tmpDir");
                        rmtree($tmpDir);
                        print("INFO: Remove temp dir:$tmpDir\n");
                    }
                }

                Utils::copyDeployDesc( $appName, $appfilePath, dirname($targetDir), $descTarget, $ostype );

                if ( -d $dmgrTarget ) {
                    Utils::copyDeployDesc( $appName, $appfilePath, dirname($targetDir), $dmgrTarget, $ostype );
                }

            }
        }
        elsif ( $appFile =~ /\.ear$/ ) {
            my $descTarget = "$wasprofile/config/cells/$cellname/applications/$appFile/deployments/$appName";
            my $dmgrTarget = "$dmgrprofile/config/cells/$cellname/applications/$appName.ear/deployments/$appName";

            my $appDir = $sectionConfig->{ lc($appName) . ".targetdir" };
            if ( defined($appDir) and $appDir ne '' ) {
                $targetDir = "$appDir/$appName.ear";
            }
            else {
                $targetDir = "$wasprofile/installedApps/$cellname/$appName.ear";
            }

            if ( -d $targetDir and -d $descTarget ) {
                $isFirstDeploy = 0;

                #remove the was tmp workdir for app
                foreach my $serverName (@serverNames) {

                    #/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/temp/cooaap1uNode01/server1/demoear
                    my $tmpdir = "$wasprofile/temp/$nodename/$serverName/$appName";
                    if ( -d $tmpdir ) {
                        rmtree($tmpdir);
                        print("INFO: Remove temp dir:$tmpdir\n");
                    }
                }

                Utils::copyDeployDesc( $appName, $appfilePath, $targetDir, $descTarget, $ostype );

                if ( -d $dmgrTarget ) {
                    Utils::copyDeployDesc( $appName, $appfilePath, $targetDir, $dmgrTarget, $ostype );
                }
            }
        }
        else {
            my $suffix = $appFile;
            print("ERROR: file type of $appFile is not supported.\n");
            $rc = 1;
        }
    }
}

exit($rc);

