#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

use POSIX qw(uname);
use Utils;
use CommonConfig;
use WlsDeployer;

sub getServerLsnPort {
    my ( $config, $servername, $appNames ) = @_;

    my $lsnPort;
    foreach my $appname (@$appNames) {
        undef($lsnPort);
        my $checkUrl = $config->{"$servername.$appname.checkurl"};
        if ( defined($checkUrl) and $checkUrl ne '' ) {
            if ( $checkUrl =~ /:(\d+)$/ or $checkUrl =~ /:(\d+)\// ) {
                $lsnPort = $1;
            }
            elsif ( $checkUrl =~ /^https:/ ) {
                $lsnPort = 443;
            }
            elsif ( $checkUrl =~ /^http:/ ) {
                $lsnPort = 80;
            }
        }
        if ( defined($lsnPort) ) {
            last;
        }
    }

    return $lsnPort;
}

sub findWindowsWlsProcess {
    my ( $servername, $lsnPort ) = @_;
    my $pidMaybe;
    my $lsnPortMatched    = 0;
    my $processComAndPids = `powershell \"Get-WmiObject Win32_Process -Filter \\\"name = 'java.exe'\\\" | Select-Object CommandLine,processid |format-list\"`;
    my $matchCount        = 0;
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
            print("WARN: Find multiple process matched 'weblogic.Name=$servername', please config checkurl to distinguish the process.\n");
        }
    }

    #print("DEBUG: pid:$pid\n");
    return $pid;
}

sub getServerPid {
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

    my $wlsHome    = $config->{"wls_home"};
    my $javaHome   = $config->{"java_home"};
    my $domainDir  = $config->{"domain_home"};
    my $wlsUser    = $config->{"wls_user"};
    my $wlsPwd     = $config->{"wls_pwd"};
    my $standalone = int( $config->{"standalone"} );
    my $adminUrl   = $config->{"admin_url"};
    $adminUrl =~ s/^http/t3/i;

    my $appnames = $config->{"appname"};
    $appnames =~ s/\s*//g;
    my @appNames = split( ",", $appnames );

    my $appfiles = $config->{"appfile"};
    $appfiles =~ s/\s*//g;
    my @appFiles = split( ",", $appfiles );

    my $servernames = $config->{"servername"};
    $servernames =~ s/\s*//g;
    my @serverNames = split( ",", $servernames );

    if ( scalar(@appNames) != scalar(@appFiles) ) {
        print("ERROR: Config error, appfile number is not same as appname number.\n");
        exit(1);
    }

    my $stopTimeout = $config->{'stop_timeout'};
    if ( not defined($stopTimeout) or $stopTimeout eq '' ) {
        $stopTimeout = 300;
    }

    my $timeout = int($stopTimeout);

    if ( defined($domainDir) and $domainDir ne '' and defined($servernames) and $servernames ne '' ) {
        $ENV{MW_HOME}   = $wlsHome  if ( defined($wlsHome)  and $wlsHome ne '' );
        $ENV{JAVA_HOME} = $javaHome if ( defined($javaHome) and $javaHome ne '' );

        my $servername;

        #my $_wlsHome = $wlsHome;
        #$_wlsHome =~ s/[[\{\}\(\)\[\]\'\"\\\/\$]/_/g;
        #$_wlsHome =~ s/\s*\r\n//g;
        foreach $servername (@serverNames) {
            my $lsnPort = getServerLsnPort( $config, $servername, \@appNames );
            $ENV{SERVER_NAME} = $servername;
            $ENV{ADMIN_URL}   = $adminUrl;
            my $checkWlsStop = sub {
                my ( $checkCount, $sleepTime ) = @_;
                if ( not defined($checkCount) ) {
                    $checkCount = 10;
                }
                if ( $checkCount < 1 ) {
                    $checkCount = 1;
                }
                if ( not defined($sleepTime) ) {
                    $sleepTime = 2;
                }

                my $isStop = 0;
                my $pid;
                while ( $checkCount > 0 ) {
                    $pid = getServerPid( $ostype, $domainDir, $servername, $lsnPort );
                    $pid =~ s/\s+/ /g;
                    if ( not defined($pid) or $pid eq '' or $pid eq ' ' ) {
                        last;
                    }
                    $checkCount = $checkCount - 1;
                    sleep($sleepTime);
                }

                if ( defined($pid) and $pid ne '' and $pid ne ' ' ) {
                    $pid = getServerPid( $ostype, $domainDir, $servername, $lsnPort, $pid );
                    print("INFO: Weblogic pid is:$pid\n");
                    $pid =~ s/\s+/ /g;
                    if ( $ostype eq 'windows' ) {
                        system("taskkill /pid $pid");
                    }
                    else {
                        system("kill $pid");
                    }
                    sleep(3);

                    $pid = getServerPid( $ostype, $domainDir, $servername, $lsnPort, $pid );
                    $pid =~ s/\s+/ /g;
                    if ( not defined($pid) or $pid eq '' or $pid eq ' ' ) {
                        print("INFO: Server $servername has been stopped.\n");
                    }
                    else {
                        print("INFO: Server $servername stop failed,pid is $pid try to kill -9.\n");
                        if ( $ostype eq 'windows' ) {
                            system("taskkill /f /pid $pid");
                        }
                        else {
                            system("kill -9 $pid");
                        }
                        sleep(3);
                    }
                }
                else {
                    $isStop = 1;
                    print("INFO: Server $servername  is stoped.\n");
                }

                return $isStop;
            };

            my $isAdmin = $wlsDeployer->isAdminServer($servername);
            if ($isAdmin) {
                print("INFO: Server $servername is admin server.\n");
            }

            $SIG{ALRM} = $checkWlsStop;
            alarm($timeout);

            if ( defined($wlsUser) and $wlsUser ne '' and defined($wlsPwd) and $wlsPwd ne '' ) {
                $ENV{WLS_USER} = $wlsUser;
                $ENV{WLS_PW}   = $wlsPwd;
            }

            my $cmd;
            if ( $ostype eq 'windows' ) {
                if ( $standalone == 1 or $isAdmin ) {
                    $cmd = "\"$domainDir/bin/stopWebLogic.$shellExt\" \"$wlsUser\" \"$wlsPwd\"";
                }
                else {
                    $ENV{ADMIN_URL}   = $adminUrl;
                    $ENV{SERVER_NAME} = $servername;

                    #$cmd = "\"$domainDir/bin/stopManagedWebLogic.$shellExt\" \"$servername\" \"$adminUrl\" \"$wlsUser\" \"$wlsPwd\"";
                    if ( defined($wlsUser) and $wlsUser ne '' and defined($wlsPwd) and $wlsPwd ne '' ) {
                        $cmd = "\"$domainDir/bin/stopWebLogic.$shellExt\" \"$wlsUser\" \"$wlsPwd\"";
                    }
                    else {
                        $cmd = "\"$domainDir/bin/stopWebLogic.$shellExt\"";
                    }
                }
            }
            else {
                if ( $standalone == 1 or $isAdmin ) {
                    $cmd = "'$domainDir/bin/stopWebLogic.$shellExt' '$wlsUser' '$wlsPwd'";
                }
                else {
                    $ENV{ADMIN_URL}   = $adminUrl;
                    $ENV{SERVER_NAME} = $servername;

                    #$cmd = "'$domainDir/bin/stopManagedWebLogic.$shellExt' '$servername' '$adminUrl' '$wlsUser' '$wlsPwd'";
                    if ( defined($wlsUser) and $wlsUser ne '' and defined($wlsPwd) and $wlsPwd ne '' ) {
                        $cmd = "'$domainDir/bin/stopWebLogic.$shellExt' '$wlsUser' '$wlsPwd'";
                    }
                    else {
                        $cmd = "'$domainDir/bin/stopWebLogic.$shellExt'";
                    }
                }
            }

            my $ret    = system("$cmd 2>&1");
            my $isStop = &$checkWlsStop( 1, 1 );
            if ( $isStop == 0 ) {
                $isStop = &$checkWlsStop( 1, 1 );
            }

            if ( $ret ne 0 ) {
                my $pos = rindex( $cmd, "\"$wlsPwd\"" );
                if ( $pos == -1 ) {
                    $pos = rindex( $cmd, "'$wlsPwd'" );
                }
                if ( $pos > 0 ) {
                    pos($cmd) = $pos;
                    $cmd =~ s/\G\"$wlsPwd\"/\"------\"/g;
                    $cmd =~ s/\G\'$wlsPwd\'/\'------\'/g;
                }

                print("WARN: Exec $cmd failed.\n");
            }

            if ( $isStop == 0 ) {
                $rc = 2;
                print("ERROR: Stop weblogic server $servername failed.\n");
            }
            else {
                $rc = 0;
                print("INFO: Stop weblogic server $servername  succeed.\n");
            }

        }
    }
    else {
        print("ERROR: No domain dir or server name found in the config file.\n");
        $rc = 1;
    }

    return $rc;
}

exit main();

