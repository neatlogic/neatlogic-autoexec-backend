#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

#use Data::Dumper;
use Utils;
use CommonConfig;
use Cwd 'abs_path';
use WlsDeployer;

sub main {
    my $rc = 0;

    if ( scalar(@ARGV) < 1 ) {
        my $progName = $FindBin::Script;
        print("ERROR:use as $progName config-name instance-name\n");
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
                print("FINE: stop $appName suceed.\n");

                #if ( $wlsDeployer->removeAppTmp( $serverName, $appName ) ) {
                #    print("INFO: remove $appName tmp dir succeed.\n");
                #}
                #else {
                #    print("ERROR: remove $appName tmp dir failed.\n");
                #    $rc = 5;
                #}
            }
            else {
                print("ERROR: stop $appName failed.\n");
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
