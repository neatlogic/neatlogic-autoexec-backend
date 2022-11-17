#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

use POSIX qw(uname);
use Utils;
use CommonConfig;
use WlsDeployer;

sub getNodeManagerPid {
    my ($wlsHome) = @_;
    $wlsHome =~ s/\\/\//g;
    my $fatWlsHome = $wlsHome;
    $fatWlsHome =~ s/\/([^\/]{6})[^\/]{2}[^\/]+(?=\/)/\/$1~\\d+/g;

    my $pid;
    my $processComAndPids = `powershell \"Get-WmiObject Win32_Process -Filter \\\"name = 'java.exe'\\\" | Select-Object CommandLine,processid |format-list\"`;
    foreach my $processComAndPid ( split( /CommandLine\s+:\s+/, $processComAndPids, 0 ) ) {
        $processComAndPid =~ s/[\r\n\t]+//g;
        $processComAndPid =~ s/\s+/ /g;
        $processComAndPid =~ s/\\/\//g;

        if ( ( $processComAndPid =~ /\Q$wlsHome\E/ or $processComAndPid =~ /$fatWlsHome/ ) and $processComAndPid =~ /weblogic\.NodeManager/ ) {
            $pid = $1 if ( $processComAndPid =~ /processid:(\d+)/ );
        }
    }

    return $pid;
}

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

    my $wlsDeployer = WlsDeployer->new( $configName, $insName );

    chdir( $wlsDeployer->getHomePath() );

    my $config = $wlsDeployer->getConf();

    my $wlsHome = $config->{"wls_home"};

    my $timeout = 300;

    my $pid;

    if ( $ostype ne 'windows' ) {
        $pid = `ps auxeww |grep '$wlsHome'|grep weblogic.NodeManager|grep -v grep|awk '{print \$2}'`;
        if ( defined($pid) and $pid ne '' ) {
            my $waitCount = 0;
            while ( $waitCount < 3 and kill($pid) eq 0 ) {
                $waitCount = $waitCount + 1;
                sleep(1);
            }

            kill( 9, $pid );
        }
        $pid = `ps auxeww |grep '$wlsHome'|grep weblogic.NodeManager|grep -v grep|awk '{print \$2}'`;

        my $waitCount = 0;
        while ( $waitCount < 3 and kill($pid) eq 0 ) {
            $waitCount = $waitCount + 1;
            sleep(1);
        }
    }
    else {
        $pid = getNodeManagerPid($wlsHome);

        if ( defined($pid) and $pid ne '' ) {
            system("taskkill /pid $pid");
        }

        my $waitCount = 0;
        $pid = getNodeManagerPid($wlsHome);
        while ( $waitCount < 3 and defined($pid) ) {
            $waitCount = $waitCount + 1;
            sleep(1);
            $pid = getNodeManagerPid($wlsHome);
        }

        if ( defined($pid) and $pid ne '' ) {
            system("taskkill /f /pid $pid");
        }

        $waitCount = 0;
        $pid       = getNodeManagerPid($wlsHome);
        while ( $waitCount < 3 and defined($pid) ) {
            $waitCount = $waitCount + 1;
            sleep(1);
            $pid = getNodeManagerPid($wlsHome);
        }
    }

    if ( not defined($pid) or $pid eq '' ) {
        print("INFO: Stop nodemanager succeed.\n");
    }
    else {
        print("ERROR: Stop nodemanager failed.\n");
        exit(-1);
    }

    return $rc;
}

exit main();

