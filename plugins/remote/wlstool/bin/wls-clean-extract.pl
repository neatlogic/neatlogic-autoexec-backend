#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

#use Data::Dumper;
use Utils;
use CommonConfig;
use Cwd 'abs_path';
use WlsDeployer;
use File::Basename;
use File::Copy;
use File::Path;
use POSIX qw(uname);

sub main {
    my $rc = 0;
    umask(022);
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

    if ( scalar(@ARGV) < 1 ) {
        my $progName = $FindBin::Script;
        print("ERROR:use as $progName config-name instance-name\n");
        exit(1);
    }

    my $configName = $ARGV[0];
    my $insName    = $ARGV[1];
    my $packName   = $ARGV[2];

    my $wlsDeployer = WlsDeployer->new( $configName, $insName );

    my $homePath = $wlsDeployer->getHomePath();

    if ( $ostype eq "windows" ) {
        $ENV{PATH} = "$homePath\\..\..\\7-Zip;" . $ENV{ProgramFiles} . "\\7-Zip;" . $ENV{PATH};
    }

    chdir($homePath);

    my $config = $wlsDeployer->getConf();

    my $domainHome = $config->{'domain_home'};
    my $needDeploy = $config->{'need_deploy'};

    my $myServerNamesStr = $config->{"servername"};
    $myServerNamesStr =~ s/\s*//g;
    my @myServerNames = split( ",", $myServerNamesStr );

    my $appfile = $config->{'appfile'};
    if ( defined($appfile) and $appfile ne '' ) {
        $packName = basename($appfile);
    }

    my $pkgsDir = $config->{"pkgs_dir"};
    if ( not defined($pkgsDir) or $pkgsDir eq '' ) {
        $pkgsDir = "$homePath/pkgs";
    }

    my $appnames = $config->{'appname'};
    $appnames =~ s/\s*//g;
    my @appNames = split( ",", $appnames );

    my $appfilePath = "$pkgsDir/$insName/$packName";
    if ( -f $appfile or $appfile =~ /^[\/\\]/ ) {
        $appfilePath = $appfile;
    }

    my $appsInfo = $wlsDeployer->getAppsConfig();

    my $appfileName = basename($appfilePath);
    if ( defined($packName) and -e $appfilePath ) {
        foreach my $appName (@appNames) {
            my $sourcePath  = $config->{"$appName.source-path"};
            my $sourceName  = basename($sourcePath);
            my $stagingMode = $config->{"$appName.staging-mode"};

            if ( defined( $appsInfo->{$appName} ) ) {
                if ( $appsInfo->{$appName}->{stagingMode} ne $stagingMode ) {
                    print("WARN: application $appName in domain config.xml stagging mode is:$appsInfo->{$appName}->{stagingMode}, not equal the config value:$stagingMode.\n");
                }
                if ( $appsInfo->{$appName}->{sourcePath} ne $sourcePath ) {
                    print("WARN: application $appName in domain config.xml source-path is:$appsInfo->{$appName}->{sourcePath}, not equal the config value:$sourcePath.\n");
                }
            }

            if ( -f $appfilePath ) {
                if ( -f $sourcePath ) {
                    if ( $sourceName eq $appfileName ) {
                        if ( $sourcePath ne $appfilePath ) {
                            if ( not File::Copy::cp( $appfilePath, $sourcePath ) ) {
                                print("ERROR: copy $appfilePath to $sourcePath failed.\n");
                                $rc = 2;
                                exit(-1);
                            }
                            else {
                                print("INFO: copy $appfilePath to $sourcePath succeed.\n");
                            }
                        }
                        else {
                            print("WARN: appfile:$appfilePath is equal to source-path:$sourcePath, no need to deploy, please check the config.\n");
                        }
                    }
                    else {
                        $rc = 3;
                        print("ERROR: app file name:$appfileName not equal to deploy name:$sourceName.\n");
                    }
                }
                elsif ( -d $sourcePath ) {
                    rmtree($sourcePath);
                    mkdir($sourcePath);
                    chdir($sourcePath);

                    my $cmd = "unzip -o $appfilePath";
                    if ( $ostype eq 'windows' ) {
                        $cmd = "7z.exe x -tzip -y \"$appfilePath\" -o\"$sourcePath\"";
                    }

                    my $ret = system($cmd);
                    if ( $ret eq 0 ) {
                        print("INFO: unzip $appfilePath to $sourcePath succeed.\n");
                    }
                    else {
                        print("ERROR: unzip $appfilePath to $sourcePath failed.\n");
                        $rc = 3;
                        exit(-1);
                    }
                }
                else {
                    if ( $appsInfo->{$appName}->{stagingMode} eq 'nostage' ) {
                        print("ERROR: $sourcePath is not exists, please check config.\n");
                        print("ERROR: can not update $appfilePath to $sourcePath.\n");
                        $rc = 4;
                        exit(-1);
                    }
                    else {
                        print("WARN: Staging mode is not nostage and source-path:$sourcePath not exists, no need to deploy.\n");
                    }
                }
            }
            elsif ( -d $appfilePath ) {
                if ( -d $sourcePath ) {
                    rmtree($sourcePath);

                    #mkdir($sourcePath);
                    #chdir("$sourcePath/..");

                    my $cmd = "cp -r $appfilePath $sourcePath";
                    if ( $ostype eq 'windows' ) {
                        $cmd = "xcopy /k /y /e \"$appfilePath\" \"$sourcePath\"";
                    }

                    my $ret = system($cmd);
                    if ( $ret eq 0 ) {
                        print("INFO: copy $appfilePath to $sourcePath succeed.\n");
                    }
                    else {
                        print("ERROR: copy $appfilePath to $sourcePath failed.\n");
                        exit(-1);
                    }
                }
                else {
                    if ( -f $sourcePath ) {
                        print("INFO: src is directory:$appfilePath and dest:$sourcePath is file, please check config.\n");
                        print("ERROR: can not update $appfilePath to $sourcePath.\n");
                        exit(-1);
                    }
                    elsif ( $appsInfo->{$appName}->{stagingMode} eq 'nostage' ) {
                        print("ERROR: $sourcePath is not exists, please check config.\n");
                        print("ERROR: can not update $appfilePath to $sourcePath.\n");
                        exit(-1);
                    }
                    else {
                        print("WARN: Staging mode is not nostage and source-path:$sourcePath not exists, no need to deploy.\n");
                    }
                }
            }
            else {
                print("ERROR: Version package $appfilePath not exists.\n");
                exit(-1);
            }
        }
    }

    foreach my $serverName (@myServerNames) {
        if ( -f $appfilePath ) {
            my $uploadPath = "$domainHome/servers/$serverName/upload/$packName/app/$packName";
            if ( -f $uploadPath ) {
                if ( File::Copy::cp( $appfilePath, $uploadPath ) ) {
                    print("INFO: copy $appfilePath to upload path:$uploadPath success.\n");
                }
                else {
                    $rc = 5;
                    print("ERROR: copy $appfilePath to upload path:$uploadPath failed:$!.\n");
                }
            }

            if ( $wlsDeployer->isAdminServer($serverName) ) {
                if ( $wlsDeployer->removeAdminTmp($serverName) ) {
                    print("INFO: remove admin tmp directory success.\n");
                }
            }
        }
    }

    foreach my $appName (@appNames) {
        foreach my $serverName (@myServerNames) {
            if ( $needDeploy eq '1' and $wlsDeployer->isAppExists($appName) == 0 ) {
                if ( $wlsDeployer->isAdminServer($serverName) ) {
                    if ( $wlsDeployer->deployApp($appName) ) {
                        print("INFO: app $appName installed.\n");
                    }
                }
            }
            else {
                if ( $wlsDeployer->removeAppTmp( $serverName, $appName ) ) {
                    print("INFO: remove $appName tmp dir succeed.\n");
                }
                else {
                    print("ERROR: remove $appName tmp dir failed.\n");
                    $rc = 5;
                }

                if ( $wlsDeployer->removeAppStage( $serverName, $appName ) ) {
                    print("INFO: remove $appName stage dir succeed.\n");
                }
                else {
                    print("ERROR: remove $appName stage dir failed.\n");
                    $rc = 6;
                }
            }
        }
    }

    return $rc;
}

exit main();
