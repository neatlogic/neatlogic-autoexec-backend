#!/usr/bin/perl
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../../patch/bin";

#use Data::Dumper;
use Utils;
use CommonConfig;
use Cwd 'abs_path';
use WlsDeployer;
use File::Basename;
use File::Copy;
use File::Path;
use POSIX qw(uname);
use File::Temp qw(tempdir);
use Patcher;

sub main {
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

    if ( scalar(@ARGV) < 1 ) {
        my $progName = $FindBin::Script;
        print("ERROR:use as $progName config-name instance-name\n");
        exit(1);
    }

    my $configName = $ARGV[0];
    my $insName    = $ARGV[1];
    my $version    = $ARGV[2];

    my $wlsDeployer = WlsDeployer->new( $configName, $insName );

    my $homePath = $wlsDeployer->getHomePath();
    if ( $ostype eq "windows" ) {
        $ENV{PATH} = "$homePath\\..\..\\7-Zip;" . $ENV{ProgramFiles} . "\\7-Zip;" . $ENV{PATH};
    }

    chdir($homePath);

    my $config = $wlsDeployer->getConf();

    my $appfile  = $config->{'appfile'};
    my $packName = $appfile;

    my $pkgsDir = $config->{"pkgs_dir"};
    if ( not defined($pkgsDir) or $pkgsDir eq '' ) {
        $pkgsDir = "$homePath/pkgs";
    }

    my $appnames = $config->{"appname"};
    $appnames =~ s/\s*//g;
    my @appNames = split( ",", $appnames );

    my $backupDir   = $config->{"backup_dir"};
    my $backupCount = int( $config->{"backup_count"} );

    my $appfilePath = "$pkgsDir/$insName/$packName";

    my $backupPath = "$pkgsDir/$insName.backup";
    if ( defined($backupDir) and $backupDir ne '' ) {
        $backupPath = $backupDir;
    }
    if ( not -e $backupPath ) {
        if ( not mkpath($backupPath) ) {
            print("ERROR: create backup dir:$backupPath failed.\n");
            $rc = 1;
            exit(-1);
        }
    }

    my $patcher = Patcher->new( $homePath, $backupPath, $backupCount );

    if ( defined($packName) and -e $appfilePath ) {
        my $appfileName = basename($appfilePath);

        foreach my $appName (@appNames) {
            my $sourcePath = $config->{"$appName.source-path"};

            #my $sourceName  = basename($sourcePath);
            my $stagingMode = $config->{"$appName.staging-mode"};

            if ( -f $sourcePath ) {
                my $backupStatus = $patcher->backup( "$insName.$appName", $version, $appfilePath, $sourcePath, 'fullbackkup' );
                if ( $backupStatus == 0 ) {
                    print("INFO: backup $sourcePath to $backupPath succeed.\n");
                }
                else {
                    print("INFO: backup $sourcePath to $backupPath failed.\n");
                    exit(-1);
                }
            }
            elsif ( -d $sourcePath ) {
                my $backupStatus = $patcher->backup( "$insName.$appName", $version, $appfilePath, $sourcePath, 'fullbackup' );
                if ( $backupStatus == 0 ) {
                    print("INFO: backup $sourcePath to $backupPath succeed.\n");
                }
                else {
                    print("INFO: backup $sourcePath to $backupPath failed.\n");
                    exit(-1);
                }
            }

            my $status = $patcher->deploy( $insName, $version, $appfilePath, $sourcePath );
            chdir($homePath);

            if ( $status eq 0 ) {
                print("INFO: version:$version patch $appfilePath to $sourcePath succeed.\n");
            }
            else {
                print("ERROR: version:$version patch $appfilePath to $sourcePath failed.\n");
                exit(-1);
            }

        }
    }

    foreach my $appName (@appNames) {
        my $srvnames = $config->{"$appName.target"};
        $srvnames =~ s/\s*//g;
        my @serverNames = split( ',', $srvnames );

        foreach my $serverName (@serverNames) {
            if ( $wlsDeployer->removeAppTmp( $serverName, $appName ) ) {
                print("INFO: remove $appName tmp dir succeed.\n");
            }
            else {
                print("ERROR: remove $appName tmp dir failed.\n");
                $rc = 2;
            }

            if ( $wlsDeployer->removeAppStage( $serverName, $appName ) ) {
                print("INFO: remove $appName stage dir succeed.\n");
            }
            else {
                print("ERROR: remove $appName stage dir failed.\n");
                $rc = 3;
            }
        }
    }

    return $rc;
}

exit main();
