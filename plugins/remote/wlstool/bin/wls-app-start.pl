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

    my $configName = $ARGV[0];
    my $insName    = $ARGV[1];

    my $wlsDeployer = WlsDeployer->new( $configName, $insName );

    chdir( $wlsDeployer->getHomePath() );

    my $config = $wlsDeployer->getConf();

    my $domainDir         = $config->{"domain_home"};
    my $customStdoutFiles = $config->{"custom_stdoutfiles"};

    my $servernames = $config->{"servername"};
    $servernames =~ s/\s*//g;
    my @serverNames = split( ",", $servernames );

    my $startTimeout = $config->{'start_timeout'};
    if ( not defined($startTimeout) or $startTimeout eq '' ) {
        $startTimeout = 300;
    }
    my $timeout = int($startTimeout);

    my $appnames = $config->{"appname"};
    $appnames =~ s/\s*//g;
    my @appNames = split( ",", $appnames );

    foreach my $appName (@appNames) {
        my $precheckUrl = $config->{"$appName.precheckurl"};
        if ( defined($precheckUrl) and $precheckUrl ne '' ) {
            if ( not Utils::CheckUrlAvailable( $precheckUrl, "GET", $timeout ) ) {
                print("ERROR: Pre-check url $precheckUrl is not available in $timeout s, starting halt.\n");
                $rc = 1;
                exit(1);
            }
        }

        if ( $wlsDeployer->isAdminServer() ) {
            if ( $wlsDeployer->startApp($appName) ) {
                print("FINE: Start $appName suceed.\n");
            }
            else {
                print("ERROR: Start $appName failed.\n");
                $rc = 2;
            }
        }
        else {
            print("INFO: This is not admin server, nothing to do.\n");
        }

        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
        my $timeSpan = sprintf( "%04d%02d%02d_%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

        foreach my $servername (@serverNames) {
            my @serverLogInfos;

            my $outFile  = "$domainDir/servers/$servername/logs/$servername.out.$timeSpan";
            my @logFiles = ("$domainDir/servers/$servername/logs/$servername.log");

            if ( defined($customStdoutFiles) and $customStdoutFiles ne '' ) {
                my @outFiles = split( /\s*,\s*/, $customStdoutFiles );
                foreach my $customStdoutFile (@outFiles) {
                    push( @logFiles, $customStdoutFile );
                }
                $outFile = $outFiles[0] . ".$timeSpan";
            }

            push( @logFiles, $outFile );

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

            my $checkUrl = $config->{"$servername.$appName.checkurl"};
            if ( defined($checkUrl) and $checkUrl ne '' ) {
                if ( Utils::CheckUrlAvailable( $checkUrl, "GET", $timeout, \@serverLogInfos ) ) {
                    print("INFO: App $appName started.\n");
                }
                else {
                    print("ERROR: App $appName start failed.\n");
                    $rc = 2;
                }
            }
        }

    }

    return $rc;
}

exit main();
