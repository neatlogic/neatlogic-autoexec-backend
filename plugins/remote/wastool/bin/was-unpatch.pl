#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../../patch/bin";

use CommonConfig;
use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Path;
use Cwd;
use Utils;
use POSIX qw(uname);
use Patcher;

my $rc = 0;
umask(022);

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
$ENV{LANG} = 'utf-8';

if ( scalar(@ARGV) != 2 ) {
    my $progName = $FindBin::Script;
    print("ERROR: Use as $progName <config-name> <instance-name> <version>\n");
    exit(1);
}

chdir($homePath);
my $mainName   = $ARGV[0];
my $configName = $mainName;
my $insName    = $ARGV[1];
my $insPrefix  = $insName;
$insPrefix =~ s/\d*$//;
my $version = $ARGV[2];

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
my $backupDir   = $sectionConfig->{"backup_dir"};
my $backupCount = int( $sectionConfig->{"backup_count"} );

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
    print("ERROR: Config error, appfile number is not same as appname number.\n");
    exit(1);
}

my $pkgsDir = $sectionConfig->{"pkgs_dir"};
if ( not defined($pkgsDir) or $pkgsDir eq '' ) {
    $pkgsDir = "$homePath/pkgs";
}

my $isFirstDeploy = 1;

if ( $needDeploy == 1 ) {
    my $backupPath = "$pkgsDir/$insName.backup";
    if ( defined($backupDir) and $backupDir ne '' ) {
        $backupPath = $backupDir;
    }
    if ( not -e $backupPath ) {
        if ( not mkpath($backupPath) ) {
            print("ERROR: Create backup dir:$backupPath failed.\n");
            exit(-1);
        }
    }
    my $patcher = Patcher->new( $homePath, $backupPath, $backupCount );

    my $appNum = scalar(@appNames);
    for ( my $i = 0 ; $i < $appNum ; $i++ ) {
        my $hasExtract = 0;
        my $appName    = $appNames[$i];
        my $appFile    = $appFiles[$i];

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

                mkpath($targetDir) if ( not -e $targetDir );

                my $rollbackStatus = $patcher->rollback( "$insName.$appName", $version );
                if ( $rollbackStatus == 0 ) {
                    print("INFO: Rollback $targetDir version $version succeed.\n");
                }
                else {
                    print("INFO: Rollback $targetDir version $version failed.\n");
                    exit(-1);
                }

                Utils::copyDeployDesc( $appName, $appfilePath, dirname($targetDir), $descTarget, $ostype );

                #my @warDescs = glob("$wasprofile/config/cells/$cellname/applications/$appName.ear/deployments/$appName/$appFile/WEB-INF/*");
                #foreach my $warDesc (@warDescs) {
                #    my $warDescFile = basename($warDesc);
                #    if ( -f "$targetDir/WEB-INF/$warDescFile" ) {
                #        File::Copy::cp( "$targetDir/WEB-INF/$warDescFile", $warDesc );
                #        print("INFO: Update descriptor file:$warDesc\n");
                #    }
                #}

                if ( -d $dmgrTarget ) {
                    Utils::copyDeployDesc( $appName, $appfilePath, dirname($targetDir), $dmgrTarget, $ostype );
                }

                $hasExtract = 1;
            }

            my $ctxRoot = $sectionConfig->{ lc($appName) . ".contextroot" };
            if ( not defined($ctxRoot) or $ctxRoot eq '' ) {
                $ctxRoot = $sectionConfig->{"contextroot"};
            }
            my $ihsTargetDir = "$ihsRoot/$ctxRoot";
            $ihsTargetDir =~ s/\/\//\//g;
            if ( defined($ihsRoot) and $ihsRoot ne '' and ( -d $ihsRoot ) and $ihsTargetDir ne '/' ) {
                if ( -d $ihsTargetDir ) {
                    my $rollbackStatus = $patcher->rollback( "$insName.$appName.warihs", $version );
                    if ( $rollbackStatus == 0 ) {
                        print("INFO: Rollback $targetDir version $version succeed.\n");
                    }
                    else {
                        print("INFO: Rollback $targetDir version $version failed.\n");
                        exit(-1);
                    }
                }

                $hasExtract = 1;
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

                #mkpath($targetDir) if ( not -e $targetDir );
                my $pkgRoot = "$pkgsDir/$insName";

                my $rollbackStatus = $patcher->rollback( "$insName.$appName", $version );
                if ( $rollbackStatus == 0 ) {
                    print("INFO: Rollback $targetDir version $version succeed.\n");
                }
                else {
                    print("INFO: Rollback $targetDir version $version failed.\n");
                    exit(-1);
                }

                Utils::copyDeployDesc( $appName, $appfilePath, $targetDir, $descTarget, $ostype );

                if ( -d $dmgrTarget ) {
                    Utils::copyDeployDesc( $appName, $appfilePath, $targetDir, $dmgrTarget, $ostype );
                }
                $hasExtract = 1;
            }

            if ( defined($ihsRoot) and $ihsRoot ne '' and ( -d $ihsRoot ) and $ihsRoot ne '/' ) {
                my $rollbackStatus = $patcher->rollback( "$insName.$appName.earihs", $version );
                if ( $rollbackStatus == 0 ) {
                    print("INFO: Rollback $ihsRoot version $version succeed.\n");
                }
                else {
                    print("INFO: Rollback $ihsRoot version $version failed.\n");
                    exit(-1);
                }
            }
        }
        else {
            my $suffix = $appFile;
            print("ERROR: File type of $appFile is not supported.\n");
            $rc = 1;
        }
    }
    if ( $isFirstDeploy == 1 and -d $wasprofile ) {
        print("WARN: Application $configName $insName not deploy yet.\n");
    }
}
else {
    print("INFO: $configName $insName not need to deploy .\n");
    exit(0);
}

exit($rc);

