#!/usr/bin/perl
package Utils;
use strict;
use File::Copy;
use File::Path;
use File::Basename;
use IO::File;
use Cwd;
use HTTP::Tiny;

my $HTTP_AGENT = 'lwp';
eval("use LWP::UserAgent");
if ($@) {
    $HTTP_AGENT = 'tiny';
}

sub execCmd {
    my ($cmd) = @_;
    if ( system($cmd) != 0 ) {
        print("ERROR: Execute $cmd failed.\n");
        exit(-1);
    }
}

sub getFileOPCmd {
    my ( $sourcePath, $targetPath, $ostype, $cmdType ) = @_;
    my $osCmd = '';
    if ( $ostype eq 'windows' ) {
        $ENV{PATH} = "$FindBin::Bin\\..\\mod\\7-Zip;" . $ENV{ProgramFiles} . "\\7-Zip;" . $ENV{PATH};

        if ( $cmdType eq 'unzip' ) {
            $osCmd = "7z x -y \"$sourcePath\" -o\"$targetPath\"";
        }
        elsif ( $cmdType eq 'zip' ) {
            $osCmd = "7z a \"$sourcePath\" \"$targetPath\"";
        }
        elsif ( $cmdType eq 'cp' ) {

            #$sourcePath =~ s/[\/\\]/\\/g;
            #$targetPath =~ s/[\/\\]/\\/g;
            if ( -d $sourcePath ) {
                my $targetBaseDir = basename($sourcePath);
                mkdir("$targetPath/$targetBaseDir") if ( not -e ("$targetPath/$targetBaseDir") );
                $osCmd = "xcopy /k /e /y \"$sourcePath\" \"$targetPath/$targetBaseDir\"";
            }
            $osCmd = "xcopy /k /y \"$sourcePath\" \"$targetPath\"" if ( -f $sourcePath );
        }
    }
    else {
        my $unzipNotExists = system("which unzip");
        my $jarCmdPath;
        if ( $unzipNotExists ne 0 ) {

            #find jar path
            my $wasPath = $ENV{WAS_PROFILE_PATH};
            $wasPath =~ s/\/profiles\/.*?$//;
            $jarCmdPath = "$wasPath/java/bin/jar";
        }

        if ( $cmdType eq 'unzip' ) {
            if ( $unzipNotExists eq 0 ) {
                $osCmd = "unzip -qo '$sourcePath' -d '$targetPath'";
            }
            else {
                $osCmd = "cd '$targetPath' && $jarCmdPath -xf '$sourcePath'";
            }
        }
        elsif ( $cmdType eq 'zip' ) {
            if ( $unzipNotExists eq 0 ) {
                $osCmd = "zip -qor $sourcePath  $targetPath";
            }
            else {
                $osCmd = "$jarCmdPath cf $sourcePath  $targetPath";
            }
        }
        elsif ( $cmdType eq 'cp' ) {
            $osCmd = "cp -pr '$sourcePath'  '$targetPath'";
        }
    }
    return $osCmd;
}

sub tailLog {
    my ( $instance, $logFile, $pos ) = @_;

    my $fh     = IO::File->new("<$logFile");
    my $newPos = 0;
    my $line;

    if ( defined($fh) ) {
        $fh->seek( 0, 2 );
        my $endPos = $fh->tell();

        if ( not defined($pos) ) {
            $pos = $endPos;
        }

        if ( $pos > $endPos ) {
            $fh->seek( 0, 0 );
        }
        else {
            $fh->seek( $pos, 0 );
        }

        while ( $line = $fh->getline() ) {
            $line =~ s/^/<$instance>:/;
            print($line);
        }

        $newPos = $fh->tell();
        $fh->close();
    }
    else {
        return -1;
    }

    return $newPos;
}

sub CheckUrl {
    my ( $url, $method, $timeout ) = @_;
    my $isSuccess = 0;

    if ( not defined($method) or $method eq '' ) {
        $method = 'GET';
    }
    if ( not defined($timeout) or $timeout eq '' ) {
        $timeout = 5;
    }
    if ( not defined($url) or $url eq '' ) {
        print("ERROR: URL not defined.\n");
        return 0;
    }

    eval {
        my $statusCode = 500;

        if ( $HTTP_AGENT eq 'lwp' ) {
            my $ua = new LWP::UserAgent;
            $ua->ssl_opts( verify_hostname => 0, SSL_verify_mode => '0', SSL_use_cert => 0 );
            $ua->timeout($timeout);
            my $response = $ua->get($url);
            $statusCode = $response->code;
        }
        else {
            my $http     = HTTP::Tiny->new();
            my $response = $http->request( 'GET', $url );
            $statusCode = $response->{status};
        }

        print("INFO: URL checking URL:$url, status code $statusCode\n");
        if ( $statusCode == 200 or $statusCode == 302 ) {
            print("INFO: URL checking URL:$url, status code $statusCode, started.\n");
            $isSuccess = 1;
        }
    };
    if ($@) {
        print("ERROR: $@\n");
    }

    return $isSuccess;
}

sub CheckUrlAvailable {
    my ( $url, $method, $timeout, $logInfos ) = @_;

    foreach my $logInfo (@$logInfos) {
        $logInfo->{pos} = tailLog( $logInfo->{server}, $logInfo->{path}, $logInfo->{pos} );
    }

    my $isSuccess = 0;
    my $step      = 3;
    my $stepCount = $timeout / $step;
    for ( my $i = 0 ; $i < $stepCount ; $i++ ) {
        print("INFO: Waiting app to start....\n");
        if ( CheckUrl( $url, $method, $step ) == 1 ) {
            $isSuccess = 1;
        }

        foreach my $logInfo (@$logInfos) {
            $logInfo->{pos} = tailLog( $logInfo->{server}, $logInfo->{path}, $logInfo->{pos} );
        }

        if ( $isSuccess == 1 ) {
            last;
        }

        sleep($step);
    }

    if ( $isSuccess == 0 ) {
        print("WARN: App url check failed.");
    }

    return $isSuccess;
}

#def copyDeployDesc(appname, appfilePath, targetdir, desctarget):
sub copyDeployDesc {
    my ( $appname, $appfilePath, $targetdir, $desctarget, $ostype ) = @_;
    my $descRoot       = dirname( dirname($desctarget) );
    my $dmgrtargetFile = "$descRoot/$appname.ear";
    if ( -f $dmgrtargetFile ) {
        my $pkgRoot = dirname($appfilePath);
        my $appfile = basename($appfilePath);

        my $cmd;
        my @statInfo = stat($dmgrtargetFile);
        my $aTime    = $statInfo[8];
        my $mTime    = $statInfo[9];

        my $curdir = Cwd::getcwd();
        chdir($pkgRoot);

        if ( $appfilePath =~ /\.war$/ ) {

            #system("cp -p $dmgrtargetFile $pkgRoot/ && zip -qo $appname.ear $appfile");
            my $copyCmd = getFileOPCmd( $dmgrtargetFile, $pkgRoot, $ostype, 'cp' );
            my $zipCmd  = getFileOPCmd( "$appname.ear",  $appfile, $ostype, 'zip' );
            if ( system($copyCmd) eq 0 ) {
                system($zipCmd);
            }

            #system("$copyCmd && $zipCmd");
            #system($zipCmd);
        }
        elsif ( $appfilePath =~ /\.ear$/ ) {

            #system("unzip -qo -d $appname.org.extract $dmgrtargetFile && unzip -qo -d $appname.extract $appfile");
            my $unzipCmd  = getFileOPCmd( $dmgrtargetFile, "$appname.org.extract", $ostype, 'unzip' );
            my $unzipCmd2 = getFileOPCmd( $appfile,        "$appname.extract",     $ostype, 'unzip' );
            if ( system($unzipCmd) eq 0 ) {
                system($unzipCmd2);
            }
            chdir("$appname.extract");
            my @jars = glob("*.jar");
            foreach my $jar (@jars) {

                #system("unzip -qo -d $jar.extract $jar && cd $jar.extract && zip -qor ../../$appname.org.extract/$jar *");
                my $unzipCmd = getFileOPCmd( $jar,                              "$jar.extract", $ostype, 'unzip' );
                my $zipCmd   = getFileOPCmd( "../../$appname.org.extract/$jar", "*",            $ostype, 'zip' );

                #system("cmd /c $unzipCmd && cd $jar.extract && $zipCmd");
                if ( system($unzipCmd) eq 0 ) {
                    chdir("$jar.extract");
                    system($zipCmd);
                    chdir("../");
                }
            }

            chdir($pkgRoot);
            my $zipCmd = getFileOPCmd( "../$appfile", "*.jar", $ostype, 'zip' );
            system("cd $appname.org.extract && $zipCmd") if ( scalar(@jars) > 0 );
        }

        #$cmd = "cp -p $appname.ear $dmgrtargetFile";
        $cmd = getFileOPCmd( "$appname.ear", $dmgrtargetFile, $ostype, 'cp' );
        utime( $aTime, $mTime, "$appname.ear" ) if ( -f "$appname.ear" );

        my $ret = system($cmd);
        print("ERROR: Update dmgr app file for $appname failed.\n") if ( $ret != 0 );

        chdir($curdir);
    }

    my $curdir = Cwd::getcwd();
    chdir($targetdir);
    my @descfiles = glob('META-INF/*.*');

    #push( @descfiles, glob('WEB-INF/*.*') );
    push( @descfiles, glob('*.war/WEB-INF/web.xml') );
    push( @descfiles, glob('*.war/META-INF/*.*') );
    push( @descfiles, glob('*.jar/META-INF/*.*') );

    foreach my $descfile (@descfiles) {
        my $descdest = "$desctarget/$descfile";
        my $descfile = "$targetdir/$descfile";
        if ( -f $descfile ) {
            my $descdir  = dirname($descdest);
            my $descname = basename($descdest);

            if ( not -d $descdir ) {
                mkpath($descdir);
            }
            if ( -f $descfile ) {
                File::Copy::cp( $descfile, $descdest );
                print("INFO: Update descriptor file:$descfile to $descdest\n");
            }

            if ( $descname eq 'web.xml' ) {
                if ( -f "$descdir/web_merged.xml" ) {
                    File::Copy::cp( $descfile, "$descdir/web_merged.xml" );
                    print("INFO: Update descriptor file:$descfile to $descdir/web_merged.xml\n");
                }
                elsif ( -f "$targetdir/web_merged.xml" ) {
                    File::Copy::cp( $descfile, "$descdir/web_merged.xml" );
                    print("INFO: Update descriptor file:$descfile to $descdir/web_merged.xml\n");
                }
            }
        }
    }
    chdir($curdir);
}

1;

