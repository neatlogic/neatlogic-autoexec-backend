#!/usr/bin/perl
use strict;
use FindBin;
use lib "$FindBin::Bin";

#use Data::Dumper;
use CommonConfig;
use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Path;
use Cwd;
use Utils;
use POSIX qw(uname);

my $rc = 0;
umask(022);

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

my $homePath = $FindBin::Bin;
$homePath = abs_path("$homePath/..");
$ENV{LANG} = 'utf-8';

if ( scalar(@ARGV) != 2 ) {
    my $progName = $FindBin::Script;
    print("ERROR:use as $progName config-name instance-name\n");
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

my $lang  = $sectionConfig->{"lang"};
my $lcAll = $sectionConfig->{"lc_all"};
$ENV{LANG}   = $lang  if ( defined($lang)  and $lang ne '' );
$ENV{LC_ALL} = $lcAll if ( defined($lcAll) and $lcAll ne '' );

my $dmgrprofile = $sectionConfig->{"dmgr_profile"};
my $standalone  = $sectionConfig->{"standalone"};
my $wasprofile  = $sectionConfig->{"was_profile"};
my $cellname    = $sectionConfig->{"cellname"};
my $nodename    = $sectionConfig->{"nodename"};
my $wasUser     = $sectionConfig->{"was_user"};
my $wasPwd      = $sectionConfig->{"was_pwd"};
my $needDeploy  = $sectionConfig->{"need_deploy"};

$ENV{WAS_PROFILE_PATH} = $wasprofile;

if ( not defined($needDeploy) or $needDeploy =~ /[1|true]/i ) {
    $needDeploy = 1;
}
else {
    $needDeploy = 0;
}

my $ihsRoot = $sectionConfig->{"ihs_docroot"};

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
    print("ERROR: config error, appfile number is not same as appname number.\n");
    exit(1);
}

my $pkgsDir = $sectionConfig->{"pkgs_dir"};
if ( not defined($pkgsDir) or $pkgsDir eq '' ) {
    $pkgsDir = "$homePath/pkgs";
}

my $isFirstDeploy = 1;
if ( $needDeploy == 1 ) {
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

            my $descTarget = "$wasprofile/config/cells/$cellname/applications/$appName.ear/deployments/$appName";
            my $dmgrTarget = "$dmgrprofile/config/cells/$cellname/applications/$appName.ear/deployments/$appName";

            my $appDir = $sectionConfig->{"$appName.targetdir"};
            if ( defined($appDir) and $appDir ne '' ) {
                $targetDir = "$appDir/$appName.ear/$appFile";
            }
            else {
                $targetDir = "$wasprofile/installedApps/$cellname/$appName.ear/$appFile";
            }

            if ( -d $targetDir and -d $descTarget ) {
                $isFirstDeploy = 0;
                foreach my $serverName (@serverNames) {
                    my $tmpDir = "$wasprofile/temp/$nodename/$serverName/$appName";
                    if ( -e $tmpDir ) {

                        #system("rm -rf $tmpDir");
                        rmtree($tmpDir);
                        print("INFO: Remove temp dir:$tmpDir\n");
                    }
                }

                #my $cleanCmd = "rm -rf $targetDir/WEB-INF/lib/*";
                print("INFO: Remove lib dir from $targetDir/WEB-INF/lib/*.\n");

                #system($cleanCmd);
                rmtree("$targetDir/WEB-INF/lib");
                print("INFO: extract package to $targetDir.\n");
                mkpath($targetDir) if ( not -e $targetDir );

                #my $extractCmd = "unzip -qo $appfilePath -d $targetDir";
                my $extractCmd = Utils::getFileOPCmd( $appfilePath, $targetDir, $ostype, 'unzip' );

                #system("$extractCmd");
                Utils::execCmd("$extractCmd");

                Utils::copyDeployDesc( $appName, $appfilePath, dirname($targetDir), $descTarget, $ostype );

                #my @warDescs = glob("$wasprofile/config/cells/$cellname/applications/$appName.ear/deployments/$appName/$appFile/WEB-INF/*");
                #foreach my $warDesc (@warDescs) {
                #    my $warDescFile = basename($warDesc);
                #    if ( -f "$targetDir/WEB-INF/$warDescFile" ) {
                #        File::Copy::cp( "$targetDir/WEB-INF/$warDescFile", $warDesc );
                #        print("INFO: Update descriptor file:$warDesc\n");
                #    }
                #}

                if ( -d $dmgrTarget ) {
                    Utils::copyDeployDesc( $appName, $appfilePath, dirname($targetDir), $dmgrTarget, $ostype );
                }

                $hasExtract = 1;
            }

            my $ctxRoot = $sectionConfig->{ lc($appName) . ".contextroot" };
            if ( not defined($ctxRoot) or $ctxRoot eq '' ) {
                $ctxRoot = $sectionConfig->{"contextroot"};
            }
            my $ihsTargetDir = "$ihsRoot/$ctxRoot";
            $ihsTargetDir =~ s/\/\//\//g;
            if ( defined($ihsRoot) and $ihsRoot ne '' and ( -d $ihsRoot ) and $ihsTargetDir ne '/' ) {
                if ( -d $ihsTargetDir ) {

                    #remove the targetdir
                    print("INFO: Remove deploy dir $ihsTargetDir.\n");
                    rmtree($ihsTargetDir);
                }

                print("INFO: Extract package to $ihsTargetDir.\n");

                #my $extractCmd = "unzip -qo $appfilePath -d $ihsTargetDir;rm -rf $ihsTargetDir/WEB-INF";
                my $extractCmd = Utils::getFileOPCmd( $appfilePath, $ihsTargetDir, $ostype, 'unzip' );

                #system("$extractCmd");
                Utils::execCmd("$extractCmd");
                rmtree("$ihsTargetDir/WEB-INF");

                $hasExtract = 1;
            }
        }
        elsif ( $appFile =~ /\.ear$/ ) {
            my $descTarget = "$wasprofile/config/cells/$cellname/applications/$appFile/deployments/$appName";
            my $dmgrTarget = "$dmgrprofile/config/cells/$cellname/applications/$appName.ear/deployments/$appName";

            my $appDir = $sectionConfig->{ lc($appName) . ".targetdir" };
            if ( defined($appDir) and $appDir ne '' ) {
                $targetDir = "$appDir/$appName.ear";
            }
            else {
                $targetDir = "$wasprofile/installedApps/$cellname/$appName.ear";
            }

            if ( -d $targetDir and -d $descTarget ) {
                $isFirstDeploy = 0;

                #remove the was tmp workdir for app
                foreach my $serverName (@serverNames) {

                    #/opt/IBM/WebSphere/AppServer/profiles/AppSrv01/temp/cooaap1uNode01/server1/demoear
                    my $tmpdir = "$wasprofile/temp/$nodename/$serverName/$appName";
                    if ( -d $tmpdir ) {
                        rmtree($tmpdir);
                        print("INFO: Remove temp dir:$tmpdir\n");
                    }
                }

                #mkpath($targetDir) if ( not -e $targetDir );
                my $pkgRoot = "$pkgsDir/$insName";

                #my $extractCmd = "unzip -qo -d $pkgRoot/$appFile.extract $pkgRoot/$appFile";
                my $extractCmd = Utils::getFileOPCmd( "$pkgRoot/$appFile", "$pkgRoot/$appFile.extract", $ostype, 'unzip' );

                #system("$extractCmd");
                Utils::execCmd("$extractCmd");

                my $curDir = Cwd::getcwd();
                chdir("$pkgRoot/$appFile.extract");

                my @jarFiles = glob("*.jar");
                for my $jarFile (@jarFiles) {
                    print("INFO: pack $jarFile to $targetDir.\n");
                    my $unzipCmd = Utils::getFileOPCmd( $jarFile,              "$jarFile.extract", $ostype, 'unzip' );
                    my $zipCmd   = Utils::getFileOPCmd( "$targetDir/$jarFile", "*",                $ostype, 'zip' );

                    #system("$unzipCmd && cd $jarFile.extract && $zipCmd");
                    #if ( system($unzipCmd) eq 0 ) {
                    #    chdir("$jarFile.extract");
                    #    system($zipCmd);
                    #    chdir("../");
                    #}
                    Utils::execCmd($unzipCmd);
                    chdir("$jarFile.extract");
                    Utils::execCmd($zipCmd);
                    chdir("../");
                }

                my @warFiles = glob("*.war");
                for my $warFile (@warFiles) {
                    print("INFO: Remove lib dir from $targetDir/$warFile/WEB-INF/lib/*.\n");

                    #system("rm -rf $targetDir/$warFile/WEB-INF/lib/*");
                    rmtree("$targetDir/$warFile/WEB-INF/lib");
                    print("INFO: extract package $warFile to $targetDir.\n");

                    #system("unzip -qo $warFile -d $targetDir/$warFile");
                    my $unzipCmd = Utils::getFileOPCmd( $warFile, "$targetDir/$warFile", $ostype, 'unzip' );

                    #system($unzipCmd);
                    Utils::execCmd($unzipCmd);
                }

                my @otherFiles = glob("*");

                for my $otherFile (@otherFiles) {
                    if ( $otherFile !~ /\.jar$/ && $otherFile !~ /\.jar\.extract$/ && $otherFile !~ /\.war$/ ) {
                        print("INFO: Remove other files $targetDir/$otherFile\n");

                        #system("rm -rf $targetDir/$otherFile && cp -pr $otherFile $targetDir");
                        rmtree("$targetDir/$otherFile");
                        my $copyCmd = Utils::getFileOPCmd( $otherFile, $targetDir, $ostype, 'cp' );

                        print("INFO: copy other files $otherFile to $targetDir\n");

                        #system($copyCmd);
                        Utils::execCmd($copyCmd);
                    }
                }

                chdir($curDir);

                Utils::copyDeployDesc( $appName, $appfilePath, $targetDir, $descTarget, $ostype );

                if ( -d $dmgrTarget ) {
                    Utils::copyDeployDesc( $appName, $appfilePath, $targetDir, $dmgrTarget, $ostype );
                }
                $hasExtract = 1;
            }

            if ( defined($ihsRoot) and $ihsRoot ne '' and ( -d $ihsRoot ) and $ihsRoot ne '/' ) {

                #if ( -d $ihsTargetDir ) {
                #    #remove the targetdir
                #
                #    print("INFO: Remove deploy dir $ihsTargetDir.\n");
                #    rmtree($ihsTargetDir);
                #}
                my $extractTmp = "$appfilePath.extract";
                print("INFO: Extract ear package to $extractTmp\n");

                #system("unzip -qo $appfilePath -d $extractTmp");
                my $unzipCmd = Utils::getFileOPCmd( $appfilePath, $extractTmp, $ostype, 'unzip' );

                #system($unzipCmd);
                Utils::execCmd($unzipCmd);

                chdir($extractTmp);
                my @warFiles = glob("*.war");
                foreach my $warFile (@warFiles) {
                    print("INFO: Extract $warFile package to $extractTmp/$warFile.extract\n");

                    #system("unzip -qo $warFile -d $warFile.extract");
                    my $unzipCmd = Utils::getFileOPCmd( "$warFile", "$warFile.extract", $ostype, 'unzip' );

                    #system($unzipCmd);
                    Utils::execCmd($unzipCmd);
                    unlink($warFile);
                    my $warContextRoot = $sectionConfig->{"$appName.$warFile.contextroot"};
                    $warContextRoot = '/' if ( not defined($warContextRoot) or $warContextRoot eq '' );
                    $warContextRoot =~ s/\/+//;

                    my $ihsTargetDir = "$ihsRoot/$warContextRoot";
                    rmtree($ihsTargetDir) if ( -d $ihsTargetDir );

                    rmtree("$warFile.extract/WEB-INF");
                    move( "$warFile.extract", $ihsTargetDir );
                }
                chdir("$extractTmp/..");
                rmtree($extractTmp) if ( -d $extractTmp );
            }
        }
        else {
            my $suffix = $appFile;
            print("ERROR: file type of $appFile is not supported.\n");
            $rc = 1;
        }
    }
    if ( $isFirstDeploy == 1 and -d $wasprofile ) {
        my $deployCmd = "$wasprofile/bin/wsadmin.$shellExt  -lang jython -user $wasUser -password $wasPwd -f $homePath/bin/was-autodeploy.py";
        if ( not defined($wasPwd) or $wasPwd eq '' ) {
            $deployCmd = "$wasprofile/bin/wsadmin.$shellExt  -lang jython -f $homePath/bin/was-autodeploy.py";
        }

        #$deployCmd = "$dmgrprofile/bin/wsadmin.sh  -lang jython -user $wasUser -password $wasPwd -f $homePath/bin/was-autodeploy.py" if ($standalone eq 0 and -d $dmgrprofile);

        $ENV{'TS_WASDEPLOYTOOL_HOME'} = $homePath;
        $ENV{'TS_WASCONF_NAME'}       = $confName;
        $ENV{'TS_WASINS_NAME'}        = $insName;
        my $pid;
        if ( $ostype eq 'windows' ) {
            my $_wasprofile = $wasprofile;
            $_wasprofile =~ s/[[\{\}\(\)\[\]\'\"\\\/\$]/_/g;
            $_wasprofile =~ s/[\s*\n]//g;
            my $processComAndPids = `powershell \"Get-WmiObject Win32_Process -Filter \\\"name = 'java.exe'\\\" | Select-Object CommandLine,processid |format-list\"`;
            foreach my $processComAndPid ( split( /CommandLine\s+:\s+/, $processComAndPids, 0 ) ) {
                $processComAndPid =~ s/[[\{\}\(\)\[\]\'\"\\\/\$]/_/g;
                $processComAndPid =~ s/[\s*\n]//g;
                if ( $processComAndPid =~ /$_wasprofile/ and $processComAndPid =~ /$nodename$servername/ ) {
                    $pid = $1 if ( $processComAndPid =~ /processid:(\d+)/ );
                }
            }
        }
        else {
            $pid = `ps auxww|grep '$wasprofile' | grep '$nodename $servername'| grep java | grep -v grep |awk '{print \$2}'`;
        }
        $ENV{'TS_SERVERPID'} = $pid;
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
            print("INFO: autodeploy failed, maybe the server not started, restart it and try again.\n");
            my $stopSrvCmd = "$homePath/bin/was-stop.pl $mainName $insName";

            #system("perl $stopSrvCmd");
            Utils::execCmd("perl $stopSrvCmd");

            foreach my $serverName (@serverNames) {
                my $startSrvCmd = "$wasprofile/bin/startServer.$shellExt $serverName -username $wasUser -password $wasPwd";
                if ( not defined($wasPwd) or $wasPwd eq '' ) {
                    $startSrvCmd = "$wasprofile/bin/startServer.$shellExt $serverName";
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
                if ( defined($checkUrl) and $checkUrl ne '' and $pid ne '' ) {
                    if ( Utils::CheckUrlAvailable( $checkUrl, "GET", 300, \@serverLogInfos ) ) {
                        print("INFO: app $appname started.\n");
                    }
                    else {
                        print("ERROR: app $appname start failed.\n");
                        $rc = 2;
                    }
                }
            }
        }
        else {
            print("INFO: Deploy complete, it will take few minutes to sync the application to other nodes, please do not restart the servers immediately.\n");
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
            foreach my $appname (@appNames) {
                my $checkUrl = $sectionConfig->{"$appname.checkurl"};
                if ( defined($checkUrl) and $checkUrl ne '' and $pid ne '' ) {
                    if ( Utils::CheckUrlAvailable( $checkUrl, "GET", 300, \@serverLogInfos ) ) {
                        print("INFO: app $appname started.\n");
                    }
                    else {
                        print("ERROR: app $appname start failed.\n");
                        $rc = 3;
                    }
                }
            }
        }
    }
}
else {
    print("INFO: $configName $insName need not deploy .\n");
    exit(0);
}

exit($rc);

