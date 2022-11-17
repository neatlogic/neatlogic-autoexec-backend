#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

use CommonConfig;
use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Path;
use Cwd;
use POSIX qw(uname);
use Utils;

my $rc = 0;

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

my $homePath = $FindBin::Bin;
$homePath = abs_path("$homePath/..");
$ENV{LANG} = 'utf-8';

if ( scalar(@ARGV) != 2 ) {
    my $progName = $FindBin::Script;
    print("ERROR: Use as $progName config-name instance-name\n");
    exit(1);
}

chdir($homePath);
my $mainName   = $ARGV[0];
my $configName = $mainName;
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

my $dmgrprofile = $sectionConfig->{"dmgr_profile"};
my $standalone  = $sectionConfig->{"standalone"};
my $wasprofile  = $sectionConfig->{"was_profile"};
my $wasUser     = $sectionConfig->{"was_user"};
my $wasPwd      = $sectionConfig->{"was_pwd"};
my $needDeploy  = $sectionConfig->{"need_deploy"};
if ( not defined($needDeploy) or $needDeploy =~ /[1|true]/i ) {
    $needDeploy = 1;
}
else {
    $needDeploy = 0;
}

my $ihsRoot = $sectionConfig->{"ihs_docroot"};

my $startTimeout = $sectionConfig->{'start_timeout'};
if ( not defined($startTimeout) or $startTimeout eq '' ) {
    $startTimeout = 300;
}
my $timeout = int($startTimeout);

my $servername = $sectionConfig->{"servername"};
$servername =~ s/\s*//g;
my @serverNames = split( ",", $servername );

my $appName = $sectionConfig->{"appname"};
$appName =~ s/\s*//g;
my @appNames = split( ",", $appName );

my $appFile = $sectionConfig->{"appfile"};
$appFile =~ s/\s*//g;
my @appFiles = split( ",", $appFile );

if ( scalar(@appNames) != scalar(@appFiles) ) {
    print("ERROR: Config error, appfile number is not same as appname number.\n");
    exit(1);
}

my $pkgsDir = $sectionConfig->{"pkgs_dir"};
if ( not defined($pkgsDir) or $pkgsDir eq '' ) {
    $pkgsDir = "$homePath/pkgs";
}

if ( $needDeploy = 1 and -d $wasprofile ) {
    foreach my $appname (@appNames) {
        my $precheckUrl = $sectionConfig->{"$appname.precheckurl"};
        if ( defined($precheckUrl) and $precheckUrl ne '' ) {
            if ( not Utils::CheckUrlAvailable( $precheckUrl, "GET", $timeout ) ) {
                print("ERROR: Pre-check url $precheckUrl is not available in $timeout s, starting halt.\n");
                exit(1);
            }
        }
    }

    my $deployCmd = "$wasprofile/bin/wsadmin.$shellExt  -lang jython -user $wasUser -password $wasPwd -f $homePath/bin/was-autodeploy.py";
    $deployCmd = "\"$wasprofile/bin/wsadmin.$shellExt\"  -lang jython -user $wasUser -password $wasPwd -f \"$homePath/bin/was-autodeploy.py\""
        if ( $ostype eq 'windows' );
    if ( not defined($wasPwd) or $wasPwd eq '' ) {
        $deployCmd = "$wasprofile/bin/wsadmin.$shellExt  -lang jython -f $homePath/bin/was-autodeploy.py";
    }

    #$deployCmd = "$dmgrprofile/bin/wsadmin.sh  -lang jython -user $wasUser -password $wasPwd -f $homePath/bin/was-autodeploy.py" if ($standalone eq 0);

    $ENV{'TS_WASDEPLOYTOOL_HOME'} = $homePath;
    $ENV{'TS_WASCONF_NAME'}       = $confName;
    $ENV{'TS_WASINS_NAME'}        = $insName;

    my @serverLogInfos;
    foreach my $servername (@serverNames) {
        my $logFile = "$wasprofile/logs/$servername/SystemOut.log";
        my $logInfo = {};
        $logInfo->{server} = $servername;
        $logInfo->{path}   = $logFile;
        $logInfo->{pos}    = -1;
        my $fh = IO::File->new("<$logFile");
        if ( defined($fh) ) {
            $logInfo->{pos} = $fh->tell();
            $fh->close();
        }

        push( @serverLogInfos, $logInfo );
    }
    my $ret = system($deployCmd);

    if ( $ret != 0 and $standalone eq 1 ) {
        print("INFO: Autodeploy failed, maybe the server not started, restart it and try again.\n");
        my $stopSrvCmd = "$homePath/bin/was-stop.pl $mainName $insName";
        $stopSrvCmd = "\"$homePath/bin/was-stop.pl $mainName $insName\"" if ( $ostype eq 'windows' );

        #system("perl $stopSrvCmd");
        Utils::execCmd("perl $stopSrvCmd");

        foreach my $serverName (@serverNames) {
            my $startSrvCmd = "$wasprofile/bin/startServer.$shellExt $serverName -username $wasUser -password $wasPwd";
            $startSrvCmd = "\"$wasprofile/bin/startServer.$shellExt\" $serverName -username $wasUser -password $wasPwd" if ( $ostype eq 'windows' );
            if ( not defined($wasPwd) or $wasPwd eq '' ) {
                $startSrvCmd = "$wasprofile/bin/startServer.$shellExt $serverName";
                $startSrvCmd = "\"$wasprofile/bin/startServer.$shellExt\" $serverName" if ( $ostype eq 'windows' );
            }

            #system($startSrvCmd);
            Utils::execCmd($startSrvCmd);
        }

        #system($deployCmd);
        Utils::execCmd($deployCmd);

        my @serverLogInfos;
        foreach my $servername (@serverNames) {
            my $logFile = "$wasprofile/logs/$servername/SystemOut.log";
            my $logInfo = {};
            $logInfo->{server} = $servername;
            $logInfo->{path}   = $logFile;
            $logInfo->{pos}    = undef;
            my $fh = IO::File->new("<$logFile");
            if ( defined($fh) ) {
                $fh->seek( 0, 2 );
                $logInfo->{pos} = $fh->tell();
                $fh->close();
            }

            push( @serverLogInfos, $logInfo );
        }

        #system($stopSrvCmd);
        print("INFO: Deploy complete, it will take few minutes to sync the application to other nodes, please do not restart the servers immediately.\n");
        foreach my $appname (@appNames) {
            my $checkUrl = $sectionConfig->{"$appname.checkurl"};
            if ( defined($checkUrl) and $checkUrl ne '' ) {
                if ( Utils::CheckUrlAvailable( $checkUrl, "GET", 300, \@serverLogInfos ) ) {
                    print("INFO: App $appname started.\n");
                }
                else {
                    print("ERROR: App $appname start failed.\n");
                    $rc = 2;
                }
            }
        }
    }
    else {
        print("INFO: Deploy complete, it will take few minutes to sync the application to other nodes, please do not restart the servers immediately.\n");
        foreach my $appname (@appNames) {
            my $checkUrl = $sectionConfig->{"$appname.checkurl"};
            if ( defined($checkUrl) and $checkUrl ne '' ) {
                if ( Utils::CheckUrlAvailable( $checkUrl, "GET", 300, \@serverLogInfos ) ) {
                    print("INFO: App $appname started.\n");
                }
                else {
                    print("ERROR: App $appname start failed.\n");
                    $rc = 3;
                }
            }
        }
    }
}

if ( $needDeploy == 1 and defined($ihsRoot) and $ihsRoot ne '' and -d $ihsRoot ) {
    my $appNum = scalar(@appNames);
    for ( my $i = 0 ; $i < $appNum ; $i++ ) {
        my $hasExtract = 0;
        my $appName    = $appNames[$i];
        my $appFile    = $appFiles[$i];

        my $appfilePath;
        if ( -e $appFile or $appFile =~ /^[\/\\]/ ) {
            $appfilePath = $appFile;
            $appFile     = basename($appFile);
        }
        else {
            $appfilePath = "$pkgsDir/$insName/$appFile";
        }

        my $targetDir = '';
        if ( $appFile =~ /\.war$/ ) {

            my $ctxRoot = $sectionConfig->{ lc($appName) . ".contextroot" };
            if ( not defined($ctxRoot) or $ctxRoot eq '' ) {
                $ctxRoot = $sectionConfig->{"contextroot"};
            }
            my $ihsTargetDir = "$ihsRoot/$ctxRoot";
            $ihsTargetDir =~ s/\/\//\//g;
            if ( defined($ihsRoot) and $ihsRoot ne '' and $ihsTargetDir ne '/' and -d $ihsTargetDir ) {
                if ( -d $ihsTargetDir ) {

                    #remove the targetdir
                    print("INFO: Remove deploy dir $ihsTargetDir.\n");
                    rmtree($ihsTargetDir);
                }

                print("INFO: Extract package to $ihsTargetDir.\n");

                #my $extractCmd = "unzip -qo $appfilePath -d $ihsTargetDir;rm -rf $ihsTargetDir/WEB-INF";
                my $extractCmd = "unzip -qo $appfilePath -d $ihsTargetDir";
                $extractCmd = "7z x $appfilePath -o$ihsTargetDir" if ( $ostype eq 'windows' );

                #system($extractCmd);
                Utils::execCmd($extractCmd);
                rmtree("$ihsTargetDir/WEB-INF");

                $hasExtract = 1;
            }
        }
        elsif ( $appFile =~ /\.ear$/ ) {
            my $ihsTargetDir = $ihsRoot;

            if ( defined($ihsRoot) and $ihsRoot ne '' and $ihsTargetDir ne '/' and ( -d $ihsTargetDir ) ) {
                if ( -d $ihsTargetDir ) {

                    #remove the targetdir
                    print("INFO: Remove deploy dir $ihsTargetDir.\n");
                    rmtree($ihsTargetDir);
                }
                print("INFO: Extract package to $ihsTargetDir\n");

                #system("unzip -qo $appfilePath -d $ihsTargetDir");
                my $unzipCmd = Utils::getFileOPCmd( $appfilePath, $ihsTargetDir, $ostype, 'unzip' );

                #system($unzipCmd);
                Utils::execCmd($unzipCmd);

                my @warFiles = glob("$targetDir/*.war");
                foreach my $warFile (@warFiles) {

                    #system("unzip -qo $warFile -d $warFile.extract");
                    my $unzipCmd = Utils::getFileOPCmd( $warFile, "$warFile.extract", $ostype, 'unzip' );

                    #system($unzipCmd);
                    Utils::execCmd($unzipCmd);
                    unlink($warFile);
                    my $warContextRoot = $sectionConfig->{"$appName.$warFile.contextroot"};
                    $warContextRoot = '/' if ( not defined($warContextRoot) or $warContextRoot eq '' );
                    $warContextRoot =~ s/\/+//;
                    move( "$warFile.extract", "$targetDir/$warContextRoot" );
                    rmtree("$warFile/WEB-INF");
                }
            }
            $hasExtract = 1;
        }
        else {
            my $suffix = $appFile;
            print("ERROR: File type of $appFile is not supported.\n");
            $rc = 1;
        }
    }
}

if ( $needDeploy != 1 ) {
    print("INFO: $configName $insName need not deploy .\n");
    exit(0);
}

exit($rc);

