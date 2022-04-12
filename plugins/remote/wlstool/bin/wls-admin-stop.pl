#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

#use Data::Dumper;
use POSIX qw(uname);
use Utils;
use CommonConfig;
use WlsDeployer;

sub getAdminLsnPort {
    my ($config) = @_;

    my $lsnPort;
    my $adminUrl = $config->{'admin_url'};
    if ( defined($adminUrl) and $adminUrl ne '' ) {
        if ( $adminUrl =~ /:(\d+)$/ or $adminUrl =~ /:(\d+)\// ) {
            $lsnPort = $1;
        }
        elsif ( $adminUrl =~ /^https:/ ) {
            $lsnPort = 443;
        }
        elsif ( $adminUrl =~ /^http:/ ) {
            $lsnPort = 80;
        }
    }

    return $lsnPort;
}

sub findWindowsWlsProcess {
    my ( $servername, $lsnPort ) = @_;
    my $pidMaybe;
    my $lsnPortMatched    = 0;
    my $processComAndPids = `powershell \"Get-WmiObject Win32_Process -Filter \\\"name = 'java.exe'\\\" | Select-Object CommandLine
,processid |format-list\"`;
    my $matchCount = 0;
    foreach my $processComAndPid ( split( /CommandLine\s+:\s+/, $processComAndPids, 0 ) ) {
        $processComAndPid =~ s/[\r\n\t]+//g;
        $processComAndPid =~ s/\s+/ /g;
        if ( $processComAndPid =~ /weblogic.Name=$servername\s/ ) {
            $matchCount = $matchCount + 1;
            if ( $processComAndPid =~ /processid\s*:\s*(\d+)/ ) {
                $pidMaybe = $1;
                if ( defined($lsnPort) ) {

                    #find the process listen port
                    my $lsnInfo = `netstat -ano | findstr $pidMaybe | findstr LISTENING | findstr :$lsnPort`;
                    if ( $lsnInfo ne '' ) {
                        $lsnPortMatched = 1;
                        last;
                    }
                }
            }
        }
    }

    my $pid;

    if ( $matchCount == 1 ) {
        $pid = $pidMaybe;
    }
    elsif ( $matchCount > 1 ) {
        if ( $lsnPortMatched == 1 ) {
            $pid = $pidMaybe;
        }
        else {
            print(
                "WARN: Find multiple process matched 'weblogic.Name=$servername', please config checkurl to distinguish the proce
ss.\n"
            );
        }
    }

    #print("DEBUG: pid:$pid\n");
    return $pid;
}

sub getAdminServerPid {
    my ( $ostype, $domainDir, $servername, $lsnPort, $currentPid ) = @_;

    my $pid;
    if ( not defined($currentPid) or $currentPid eq '' ) {
        if ( $ostype eq 'windows' ) {
            $pid = findWindowsWlsProcess( $servername, $lsnPort );
        }
        else {
            $pid = `ps auxeww|grep '$domainDir' | grep 'Name=$servername '| grep java | grep -v grep |awk '{print \$2}'`;
        }
    }
    else {
        if ( $ostype eq 'windows' ) {
            my $pidInfo = `tasklist /FI "PID eq $currentPid" | findstr $currentPid`;
            if ( $pidInfo ne '' ) {
                $pid = $currentPid;
            }
        }
        else {
            $pid = `ps auxeww|grep '$domainDir' | grep 'Name=$servername '| grep java | grep -v grep |awk '{print \$2}'`;
        }
    }

    if ( defined($pid) ) {
        $pid =~ s/\s+/ /g;
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
        print("ERROR:use as $progName config-name instance-name\n");
        exit(1);
    }

    my $configName = $ARGV[0];
    my $insName    = $ARGV[1];

    my $wlsDeployer = WlsDeployer->new( $configName, $insName );
    my $adminServerName = $wlsDeployer->getAdminServerName();

    chdir( $wlsDeployer->getHomePath() );

    my $config = $wlsDeployer->getConf();

    my $wlsHome    = $config->{"wls_home"};
    my $javaHome   = $config->{"java_home"};
    my $domainDir  = $config->{"domain_home"};
    my $wlsUser    = $config->{"wls_user"};
    my $wlsPwd     = $config->{"wls_pwd"};
    my $standalone = int( $config->{"standalone"} );
    my $adminUrl   = $config->{"admin_url"};
    $adminUrl =~ s/^http/t3/i;

    my $timeout = 300;

    if ( defined($domainDir) and $domainDir ne '' and defined($adminServerName) and $adminServerName ne '' ) {
        $ENV{MW_HOME}   = $wlsHome  if ( defined($wlsHome)  and $wlsHome ne '' );
        $ENV{JAVA_HOME} = $javaHome if ( defined($javaHome) and $javaHome ne '' );
        $ENV{ADMIN_URL} = $adminUrl;
        $ENV{SERVER_NAME} = $adminServerName;

        my $lsnPort = getAdminLsnPort($config);

        my $cmd;
        if ( $ostype eq 'windows' ) {
            if ( defined($wlsUser) and $wlsUser ne '' and defined($wlsPwd) and $wlsPwd ne '' ) {
                $cmd = "\"$domainDir/bin/stopWebLogic.$shellExt\" \"$wlsUser\" \"$wlsPwd\"";
            }
            else {
                $cmd = "\"$domainDir/bin/stopWebLogic.$shellExt\"";
            }
        }
        else {
            if ( defined($wlsUser) and $wlsUser ne '' and defined($wlsPwd) and $wlsPwd ne '' ) {
                $cmd = "'$domainDir/bin/stopWebLogic.$shellExt' '$wlsUser' '$wlsPwd'";
            }
            else {
                $cmd = "'$domainDir/bin/stopWebLogic.$shellExt'";
            }
        }

        my $ret = system("$cmd 2>&1");

        my $pos = rindex( $cmd, "\"$wlsPwd\"" );
        if ( $pos == -1 ) {
            $pos = rindex( $cmd, "'$wlsPwd'" );
        }
        if ( $pos > 0 ) {
            pos($cmd) = $pos;
            $cmd =~ s/\G\"$wlsPwd\"/\"------\"/g;
            $cmd =~ s/\G\'$wlsPwd\'/\'------\'/g;
        }

        if ( $ret != 0 ) {
            print("WARN: Exec $cmd failed.\n");
        }
        else {
            print("INFO: Exec $cmd succeed.\n");
        }

        my $waitCount = 0;
        my $pid = getAdminServerPid( $ostype, $domainDir, $adminServerName, $lsnPort );
        while ( $waitCount < 5 and defined($pid) and $pid ne '' ) {
            $waitCount = $waitCount + 1;
            sleep(1);
            $pid = getAdminServerPid( $ostype, $domainDir, $adminServerName, $lsnPort, $pid );
        }

        if ( defined($pid) and $pid ne '' ) {
            if ( $ostype eq 'windows' ) {
                system("taskkill /f /pid $pid");
            }
            else {
                system("kill -9 $pid");
            }
        }

        $waitCount = 0;
        my $pid = getAdminServerPid( $ostype, $domainDir, $adminServerName, $lsnPort, $pid );
        while ( $waitCount < 5 and defined($pid) and $pid ne '' ) {
            $waitCount = $waitCount + 1;
            sleep(1);
            $pid = getAdminServerPid( $ostype, $domainDir, $adminServerName, $lsnPort, $pid );
        }

        if ( defined($pid) and $pid ne '' ) {
            print("ERROR: stop $adminServerName failed.\n");
            $rc = 1;
        }
        else {
            print("INFO: stop $adminServerName succeed.\n");
        }
    }
    else {
        print("ERROR: no domain dir or server name found in the config file.\n");
        $rc = 1;
    }

    return $rc;
}

exit main();

