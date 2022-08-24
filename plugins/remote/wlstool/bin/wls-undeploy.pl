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
        print("ERROR: Use as $progName config-name instance-name\n");
        exit(1);
    }

    my $configName  = $ARGV[0];
    my $insName     = $ARGV[1];
    my $wlsDeployer = WlsDeployer->new( $configName, $insName );

    chdir( $wlsDeployer->getHomePath() );

    my $config = $wlsDeployer->getConf();

    my $servername = $config->{"servername"};
    my $domainDir  = $config->{"domain_home"};
    my $appNames   = $config->{"appname"};
    my $targets    = $config->{"$appNames.target"};
    $appNames =~ s/\s*//g;
    $targets  =~ s/\s*//g;
    my @appNames = split( ",", $appNames );
    my @targets  = split( ",", $targets );

    my $stopTimeout = $config->{'stop_timeout'};
    if ( not defined($stopTimeout) or $stopTimeout eq '' ) {
        $stopTimeout = 300;
    }

    my $timeout = int($stopTimeout);

    my $outFile  = "$domainDir/servers/$servername/logs/$servername.out";
    my @logFiles = ( $outFile, "$domainDir/servers/$servername/logs/$servername.log" );
    my @serverLogInfos;

    foreach my $logFile (@logFiles) {
        my $logInfo = {};
        $logInfo->{server} = $servername;
        $logInfo->{path}   = $logFile;
        $logInfo->{pos}    = undef;
        my $fh = IO::File->new("<$logFile");
        if ( defined($fh) ) {
            $fh->seek( 0, 2 );
            $logInfo->{pos} = -s $logFile;
            $fh->close();
        }
        push( @serverLogInfos, $logInfo );
    }
    foreach my $appName (@appNames) {
        if ( $wlsDeployer->isAdminServer() ) {
            if ( $wlsDeployer->isAppExists($appName) ) {
                my $undeployStatus = $wlsDeployer->undeployApp($appName);
                if ( $undeployStatus == 1 ) {
                    foreach my $target (@targets) {
                        my $checkUrl = $config->{"$target.checkurl"};
                        if ( defined($checkUrl) and $checkUrl ne '' ) {
                            if ( Utils::CheckUrlAvailable( $checkUrl, "GET", $timeout, \@serverLogInfos ) ) {
                                sleep(10);
                                print("INFO: App $appName uninstalled.\n");
                                print("INFO: Sleep ten seconds wait for synchronize\n");
                            }
                            else {
                                print("ERROR: App $appName uninstall failed.\n");
                                $rc = 2;
                            }
                        }
                    }
                    print("FINE: Undeploy $appName suceed.\n");
                }
                else {
                    print("ERROR: Undeploy $appName failed.\n");
                    $rc = 3;
                }
            }
            else {
                print("INFO: $appName not exists.\n");
            }
        }
        else {
            print("INFO: This is not admin server, nothing to do.\n");
        }
    }

    return $rc;
}

exit main();
