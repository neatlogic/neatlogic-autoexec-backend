#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";
use Utils;
use POSIX qw(uname);

my @uname    = uname();
my $ostype   = $uname[0];
my $shellExt = 'sh';
my $nullDev  = '/dev/null';

if ( $ostype =~ /Windows/i ) {
    $ostype   = 'windows';
    $shellExt = 'bat';
    $nullDev  = 'NUL';
}
else {
    $ostype   = 'unix';
    $shellExt = 'sh';
    $nullDev  = '/dev/null';
}

use CommonConfig;
use Cwd 'abs_path';
my $homePath = $FindBin::Bin;
$homePath = abs_path("$homePath/..");
$ENV{LANG} = 'utf-8';

if ( scalar(@ARGV) != 2 ) {
    my $progName = $FindBin::Script;
    print("ERROR: Use as $progName config-name instance-name\n");
    exit(1);
}

chdir($homePath);
my $configName = $ARGV[0];
my $insName    = $ARGV[1];
my $insPrefix  = $insName;
$insPrefix =~ s/\d*$//;

my $sectionConfig;
my $config = CommonConfig->new( "$homePath/conf", "wastool.ini" );
$sectionConfig = $config->getConfig("$configName.$insName");
my $confName = "$configName.$insName";
if ( not defined($sectionConfig) ) {
    $sectionConfig = $config->getConfig("$configName.$insPrefix");
    $confName      = "$configName.$insPrefix";
}
if ( not defined($sectionConfig) ) {
    $confName      = $configName;
    $sectionConfig = $config->getConfig("$configName");
}
my $wasprofile = $sectionConfig->{"was_profile"};
my $cellname   = $sectionConfig->{"cellname"};
my $nodeName   = $sectionConfig->{"nodename"};
my $wasUser    = $sectionConfig->{"was_user"};
my $wasPwd     = $sectionConfig->{"was_pwd"};

my $ihsDir = $sectionConfig->{"ihs_dir"};

my $stopTimeout = $sectionConfig->{'stop_timeout'};
if ( not defined($stopTimeout) or $stopTimeout eq '' ) {
    $stopTimeout = 300;
}

#print("debug $needDeploy,$wasprofile,$cellname,$appfile,$appname,$wasUser,$wasPwd\n");

my $appnames = $sectionConfig->{"appname"};
$appnames =~ s/\s*//g;
my @appNames = split( ",", $appnames );

my $appfiles = $sectionConfig->{"appfile"};
$appfiles =~ s/\s*//g;
my @appFiles = split( ",", $appfiles );

my $servernames = $sectionConfig->{"servername"};
$servernames =~ s/\s*//g;
my @serverNames = split( ",", $servernames );

if ( scalar(@appNames) != scalar(@appFiles) ) {
    print("ERROR: Config error, appfile number is not same as appname number.\n");
    exit(1);
}

my $timeout = int($stopTimeout);

if ( defined($wasprofile) and $wasprofile ne '' and defined($servernames) and $servernames ne '' ) {
    my $_wasprofile = $wasprofile;

    #$_wasprofiles = split(/[\\\/]/ , $_wasprofile, 0 );
    $_wasprofile =~ s/[[\{\}\(\)\[\]\'\"\\\/\$]/_/g;
    $_wasprofile =~ s/[\s*\n]//g;
    foreach my $servername (@serverNames) {
        my $checkWasStop = sub {
            my $checkCount = 60;
            my $pid;
            while ( $checkCount > 0 ) {
                if ( $ostype eq 'windows' ) {
                    my $processComAndPids = `powershell \"Get-WmiObject Win32_Process -Filter \\\"name = 'java.exe'\\\" | Select-Object CommandLine,processid |format-list\"`;
                    foreach my $processComAndPid ( split( /CommandLine\s+:\s+/, $processComAndPids, 0 ) ) {
                        $processComAndPid =~ s/[[\{\}\(\)\[\]\'\"\\\/\$]/_/g;
                        $processComAndPid =~ s/[\s*\n]//g;
                        if ( $processComAndPid =~ /$_wasprofile/ and $processComAndPid =~ /$nodeName$servername/ ) {
                            $pid = $1 if ( $processComAndPid =~ /processid:(\d+)/ );
                        }
                    }
                }
                else {
                    $pid = `ps auxww|grep '$wasprofile' | grep '$nodeName $servername'| grep java | grep -v grep |awk '{print \$2}'`;
                }
                $pid =~ s/\s+/ /g;
                last if ( not defined($pid) or $pid eq '' or $pid eq ' ' );
                $checkCount = $checkCount - 1;
                sleep(2);
            }

            if ( defined($pid) and $pid ne '' and $pid ne ' ' ) {
                print("INFO: WAS pid is:$pid");
                $pid =~ s/\s+/ /g;
                if ( $ostype eq 'windows' ) {
                    system("taskkill /pid $pid");
                }
                else {
                    system("kill $pid");
                }
                sleep(3);
                if ( $ostype eq 'windows' ) {
                    my $processComAndPids = `powershell \"Get-WmiObject Win32_Process -Filter \\\"name = 'java.exe'\\\" | Select-Object CommandLine,processid |format-list\"`;
                    foreach my $processComAndPid ( split( /CommandLine\s+:\s+/, $processComAndPids, 0 ) ) {
                        $processComAndPid =~ s/[[\{\}\(\)\[\]\'\"\\\/\$]/_/g;
                        $processComAndPid =~ s/[\s*\n]//g;
                        if ( $processComAndPid =~ /$_wasprofile/ and $processComAndPid =~ /$nodeName $servername\s/ ) {
                            $pid = $1 if ( $processComAndPid =~ /processid:(\d+)/ );
                        }
                    }
                }
                else {
                    $pid = `ps auxww|grep '$wasprofile' | grep '$nodeName $servername'| grep java | grep -v grep |awk '{print \$2}'`;
                }
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

                    #system("kill -9 $pid");
                    sleep(3);
                }
            }
            else {
                print("INFO: Server $servername  is stoped.\n");
            }
        };

        $SIG{ALRM} = $checkWasStop;
        alarm($timeout);

        my $cmd = "$wasprofile/bin/stopServer.$shellExt $servername -username $wasUser -password $wasPwd";
        if ( $ostype eq 'windows' ) {
            $cmd = "\"$wasprofile/bin/stopServer.$shellExt\" $servername -username $wasUser -password $wasPwd";
        }
        else {
            $cmd = "$wasprofile/bin/stopServer.$shellExt $servername -username $wasUser -password $wasPwd";
        }

        if ( not defined($wasPwd) or $wasPwd eq '' ) {
            if ( $ostype eq 'windows' ) {
                $cmd = "\"$wasprofile/bin/stopServer.$shellExt\" $servername";
            }
            else {
                $cmd = "$wasprofile/bin/stopServer.$shellExt $servername";
            }
        }

        system("$cmd");
        &$checkWasStop();
    }
}

if ( defined($ihsDir) and $ihsDir ne '' and -d $ihsDir ) {
    my $checkIhsStop = sub {
        my $checkCount = 2;
        my $pid;
        my $_ihsDir = $ihsDir;
        $_ihsDir =~ s/[\\\/\(\)]/_/g;
        while ( $checkCount > 0 ) {
            if ( $ostype eq 'windows' ) {
                my $processComAndPids = `powershell \"Get-WmiObject Win32_Process -Filter \\\"name = 'java.exe'\\\" | Select-Object CommandLine,processid |format-list\"`;
                foreach my $processComAndPid ( split( /CommandLine\s+:\s+/, $processComAndPids, 0 ) ) {
                    if ( $processComAndPid =~ /$_ihsDir/ and $processComAndPid =~ /httpd/ ) {
                        $pid = $1 if ( $processComAndPid =~ /processid\s+:\s+(\d+)/ );
                    }
                }
            }
            else {
                $pid = `ps auxww|grep '$ihsDir'|grep httpd | grep -v grep | awk '{print \$2}'`;
            }
            $pid =~ s/\s+/ /g;
            last if ( not defined($pid) or $pid eq '' or $pid eq ' ' );
            $checkCount = $checkCount - 1;
            sleep(2);
        }

        if ( defined($pid) and $pid ne '' and $pid ne ' ' ) {
            print("INFO: IHS pid is:$pid, try to kill it.\n");
            $pid =~ s/\s+/ /g;
            if ( $ostype eq 'windows' ) {
                system("taskkill /pid $pid");
            }
            else {
                system("kill $pid");
            }

            #system("kill $pid");
            sleep(3);
            if ( $ostype eq 'windows' ) {
                my $processComAndPids = `powershell \"Get-WmiObject Win32_Process -Filter \\\"name = 'java.exe'\\\" | Select-Object CommandLine,processid |format-list\"`;
                foreach my $processComAndPid ( split( /CommandLine\s+:\s+/, $processComAndPids, 0 ) ) {
                    if ( $processComAndPid =~ /$_ihsDir/ and $processComAndPid =~ /httpd/ ) {
                        $pid = $1 if ( $processComAndPid =~ /processid\s+:\s+(\d+)/ );
                    }
                }
            }
            else {
                $pid = `ps auxww|grep '$ihsDir'| grep httpd | grep -v grep | awk '{print \$2}'`;
            }
            $pid =~ s/\s+/ /g;
            if ( not defined($pid) or $pid eq '' or $pid eq ' ' ) {
                print("INFO: IHS server is stopped.\n");
            }
            else {
                print("INFO: IHS server stop failed, pid is $pid, try to kill -9.\n");
                if ( $ostype eq 'windows' ) {
                    system("taskkill /f /pid $pid");
                }
                else {
                    system("kill -9 $pid");
                }

                #system("kill -9 $pid");
                sleep(3);
            }
        }
        else {
            print("INFO: IHS server is stopped.\n");
        }
    };

    $SIG{ALRM} = $checkIhsStop;
    my $cmd;
    alarm($timeout);
    if ( $ostype eq 'windows' ) {
        $cmd = "\"$ihsDir/bin/apachectl\" stop";
    }
    else {
        $cmd = "$ihsDir/bin/apachectl stop";
    }
    system($cmd);
    &$checkIhsStop();
}

