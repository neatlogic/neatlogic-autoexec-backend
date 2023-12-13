#!/usr/bin/perl
use strict;

use FindBin;
use lib "$FindBin::Bin";
use lib "$FindBin::Bin/../../patch/bin";

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
        print("ERROR: Use as $progName config-name instance-name\n");
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
    if ( defined($appfile) and $appfile ne '' ) {
        $packName = basename($appfile);
    }

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
    if ( -f $appfile or $appfile =~ /^[\/\\]/ ) {
        $appfilePath = $appfile;
    }

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

    foreach my $appName (@appNames) {
        my $sourcePath = $config->{"$appName.source-path"};

        my $rollbackStatus = $patcher->rollback( "$insName.$appName", $version );
        if ( $rollbackStatus == 0 ) {
            print("INFO: Rollback $sourcePath version $version succeed.\n");
        }
        else {
            print("INFO: Rollback $sourcePath version $version failed.\n");
            exit(-1);
        }

    }

    foreach my $appName (@appNames) {
        my $srvnames = $config->{"$appName.target"};
        $srvnames =~ s/\s*//g;
        my @serverNames = split( ',', $srvnames );

        foreach my $serverName (@serverNames) {
            if ( $wlsDeployer->removeAppTmp( $serverName, $appName ) ) {
                print("INFO: Remove $appName tmp dir succeed.\n");
            }
            else {
                print("ERROR: Remove $appName tmp dir failed.\n");
                $rc = 2;
            }

            if ( $wlsDeployer->removeAppStage( $serverName, $appName ) ) {
                print("INFO: Remove $appName stage dir succeed.\n");
            }
            else {
                print("ERROR: Remove $appName stage dir failed.\n");
                $rc = 3;
            }
        }
    }

    return $rc;
}

exit main();
