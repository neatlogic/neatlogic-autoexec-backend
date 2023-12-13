#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

use Utils;
use CommonConfig;
use Cwd 'abs_path';
use WlsDeployer;

sub main {
    my $rc = 0;

    if ( scalar(@ARGV) < 1 ) {
        my $progName = $FindBin::Script;
        print("ERROR: Use as $progName config-name instance-name\n");
        exit(1);
    }

    my $configName = $ARGV[0];
    my $insName    = $ARGV[1];

    my $wlsDeployer = WlsDeployer->new( $configName, $insName );

    chdir( $wlsDeployer->getHomePath() );

    my $config = $wlsDeployer->getConf();

    my $appnames = $config->{"appname"};
    $appnames =~ s/\s*//g;
    my @appNames = split( ",", $appnames );

    foreach my $appName (@appNames) {
        if ( $wlsDeployer->isAdminServer() ) {
            if ( $wlsDeployer->stopApp($appName) ) {
                print("FINE: Stop $appName suceed.\n");

                #if ( $wlsDeployer->removeAppTmp( $serverName, $appName ) ) {
                #    print("INFO: Remove $appName tmp dir succeed.\n");
                #}
                #else {
                #    print("ERROR: Remove $appName tmp dir failed.\n");
                #    $rc = 5;
                #}
            }
            else {
                print("ERROR: Stop $appName failed.\n");
                $rc = 2;
            }

        }
        else {
            print("INFO: This is not admin server, nothing to do.\n");
        }
    }

    return $rc;
}

exit main();
