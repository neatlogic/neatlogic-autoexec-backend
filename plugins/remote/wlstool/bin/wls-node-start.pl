#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

#use Data::Dumper;
use POSIX qw(uname);
use Utils;
use CommonConfig;
use WlsDeployer;

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

    #set log file's default permission
    umask(0022);

    if ( scalar(@ARGV) < 1 ) {
        my $progName = $FindBin::Script;
        print("ERROR:use as $progName config-name instance-name\n");
        exit(1);
    }

    my $configName = $ARGV[0];
    my $insName    = $ARGV[1];

    if ( scalar(@ARGV) > 2 ) {
        my $argsLen = scalar(@ARGV);
        my $i;
        for ( $i = 2 ; $i < $argsLen ; $i++ ) {
            my $envLine = $ARGV[$i];
            if ( $envLine =~ /\s*(\w+)\s*=\s*(.*)\s*$/ ) {
                $ENV{$1} = $2;
            }
        }
    }

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

    my $maxLogSize = $config->{"max_logsize"};
    if ( not defined($maxLogSize) or int($maxLogSize) == 0 ) {
        $maxLogSize = 2048;
    }

    my $maxLogFiles = $config->{"max_logfiles"};
    if ( not defined($maxLogFiles) or int($maxLogFiles) == 0 ) {
        $maxLogFiles = 123;
    }

    my $maxLogDays = $config->{"max_logdays"};
    if ( not defined($maxLogDays) or int($maxLogDays) == 0 ) {
        $maxLogDays = 93;
    }

    my $startTimeout = $config->{'start_timeout'};
    if ( not defined($startTimeout) or $startTimeout eq '' ) {
        $startTimeout = 300;
    }

    my $timeout = int($startTimeout);

    if ( defined($domainDir) and $domainDir ne '' and defined($adminServerName) and $adminServerName ne '' ) {
        $ENV{MW_HOME}   = $wlsHome  if ( defined($wlsHome)  and $wlsHome ne '' );
        $ENV{JAVA_HOME} = $javaHome if ( defined($javaHome) and $javaHome ne '' );

        my @serverLogInfos;

        my $outFile = "$wlsHome/wlserver/common/nodemanager/nodemanager.out";

        #/app/serverware/wls/wls1036/wlserver/common/nodemanager/nodemanager.log
        my @logFiles = ( "$wlsHome/wlserver/common/nodemanager/nodemanager.log", $outFile );

        foreach my $logFile (@logFiles) {
            my $logInfo = {};
            $logInfo->{server} = $adminServerName;
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

        $ENV{SERVER_NAME}      = $adminServerName;
        $ENV{TS_INSTANCE_NAME} = $adminServerName;

        my $binPath = $FindBin::Bin;

        my $cmd;
        if ( $ostype eq 'windows' ) {
            $cmd = "\"$wlsHome/wlserver/server/bin/startNodeManager.$shellExt\"";
            $cmd = "start cmd /c \"$cmd\" 2>&1 | perl \"$binPath/logrotate\" --max_days $maxLogDays --max_files $maxLogFiles --max_size $maxLogSize \"$outFile\"\" && exit";
        }
        else {
            $cmd = "'$wlsHome/wlserver/server/bin/startNodeManager.$shellExt'";
            $cmd = "nohup $cmd 2>&1 | perl '$binPath/logrotate' --max_days $maxLogDays --max_files $maxLogFiles --max_size $maxLogSize '$outFile' &";
        }

        my $ret = system($cmd);

        if ( $ret != 0 ) {
            print("ERROR: Exec $cmd failed.\n");
            $rc = $ret;
        }
        else {
            print("INFO: Exec $cmd succeed.\n");
        }

        if ( Utils::CheckUrlAvailable( undef, "GET", $timeout, \@serverLogInfos, 'INFO: Plain socket listener started on port' ) ) {
            print("INFO: nodemanager started.\n");
        }
        else {
            print("ERROR: nodemanager start failed.\n");
            $rc = 2;
        }

        if ( $ostype eq 'windows' ) {
            for ( my $i = 1 ; $i <= 3 ; $i++ ) {
                print("\x1b[[-=-exec finish-=-\x1b]]\r\n$rc\r\n");
                sleep(1);
            }
        }
    }
    else {
        print(" ERROR : no domain dir or server name found in the config file . \n ");
        $rc = 1;
    }

    return $rc;
}

exit main();

