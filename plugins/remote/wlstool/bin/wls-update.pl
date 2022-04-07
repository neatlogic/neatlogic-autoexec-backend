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
    if ( scalar(@ARGV) < 1 ) {
        my $progName = $FindBin::Script;
        print("ERROR:use as $progName config-name instance-name\n");
        exit(1);
    }

    my $configName  = $ARGV[0];
    my $insName     = $ARGV[1];
    my $wlsDeployer = WlsDeployer->new( $configName, $insName );

    chdir( $wlsDeployer->getHomePath() );

    my $config = $wlsDeployer->getConf();

    my $servername        = $config->{"servername"};
    my $domainDir         = $config->{"domain_home"};
    my $customStdoutFiles = $config->{"custom_stdoutfiles"};

    my $appNames = $config->{"appname"};
    my $targets  = $config->{"$appNames.target"};
    $appNames =~ s/\s*//g;
    $targets =~ s/\s*//g;
    my @appNames = split( ",", $appNames );
    my @targets  = split( ",", $targets );

    my $startTimeout = $config->{'start_timeout'};
    if ( not defined($startTimeout) or $startTimeout eq '' ) {
        $startTimeout = 300;
    }
    my $timeout = int($startTimeout);

    foreach my $appname (@appNames) {
        my $precheckUrl = $config->{"$appname.precheckurl"};
        if ( defined($precheckUrl) and $precheckUrl ne '' ) {
            if ( Utils::CheckUrlAvailable( $precheckUrl, "GET", $timeout ) ) {
                print("ERROR: pre-check url $precheckUrl is not available in $timeout s, starting halt.\n");
                exit(1);
            }
        }
    }

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
    my $timeSpan = sprintf( "%04d%02d%02d_%02d%02d%02d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

    my $outFile  = "$domainDir/servers/$servername/logs/$servername.out.$timeSpan";
    my @logFiles = ("$domainDir/servers/$servername/logs/$servername.log");

    if ( defined($customStdoutFiles) and $customStdoutFiles ne '' ) {
        my @outFiles = split( /\s*,\s*/, $customStdoutFiles );
        foreach my $customStdoutFile (@outFiles) {
            push( @logFiles, $customStdoutFile );
        }
        $outFile = $outFiles[0] . ".$timeSpan";
    }
    else {
        push( @logFiles, $outFile );
    }

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
            if ( $wlsDeployer->updateApp($appName) ) {
                foreach my $tagets (@targets) {
                    my $checkUrl = $config->{"$tagets.checkurl"};
                    if ( defined($checkUrl) and $checkUrl ne '' ) {
                        if ( Utils::CheckUrlAvailable( $checkUrl, "GET", $timeout, \@serverLogInfos ) ) {
                            print("INFO: app $appName installed.\n");
                        }
                        else {
                            print("ERROR: app $appName install failed.\n");
                        }
                    }
                }
                print("FINEST: update $appName suceed.\n");
            }
            else {
                print("ERROR: update $appName failed.\n");
            }
        }
        else {
            print("INFO: This is not admin server, nothing to do.\n");
        }
    }
}

main();
