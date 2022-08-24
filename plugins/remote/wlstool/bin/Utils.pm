#!/usr/bin/perl
package Utils;
use strict;
use File::Copy;
use File::Path;
use File::Basename;
use IO::File;
use IO::Socket::INET;
use Cwd;
use HTTP::Tiny;

sub tailLog {
    my ( $instance, $logFile, $pos, $matchRegExp ) = @_;

    my $fh     = IO::File->new("<$logFile");
    my $newPos = 0;
    my $line;

    my $isMatched = 0;

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
            if ( defined($matchRegExp) ) {
                if ( $line =~ /$matchRegExp/ ) {
                    $isMatched = 1;
                }
            }
            $line =~ s/^/<$instance>:/;
            print($line);
        }

        $newPos = $fh->tell();
        $fh->close();
    }
    else {
        return -1;
    }

    return ( $newPos, $isMatched );
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

        my $http     = HTTP::Tiny->new();
        my $response = $http->request( 'GET', $url );
        $statusCode = $response->{status};

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
    my ( $url, $method, $timeout, $logInfos, $matchRegExp ) = @_;

    my $isMatched = 0;
    foreach my $logInfo (@$logInfos) {
        ( $logInfo->{pos}, $isMatched ) = tailLog( $logInfo->{server}, $logInfo->{path}, $logInfo->{pos}, $matchRegExp );
    }
    if ( $isMatched == 1 ) {
        return 1;
    }

    my $isSuccess = 0;
    my $step      = 3;
    my $stepCount = $timeout / $step;
    for ( my $i = 0 ; $i < $stepCount ; $i++ ) {
        print("INFO: Waiting app to start....\n");
        if ( defined($url) ) {
            if ( $url =~ /^http|^https/ and CheckUrl( $url, $method, $step ) == 1 ) {
                $isSuccess = 1;
            }
            else {
                my ( $host, $port ) = split( /:/, $url );
                if ( IO::Socket::INET->new( PeerAddr => $host, PeerPort => $port, Proto => 'tcp' ) ) {
                    $isSuccess = 1;
                }
            }
        }

        foreach my $logInfo (@$logInfos) {
            ( $logInfo->{pos}, $isMatched ) = tailLog( $logInfo->{server}, $logInfo->{path}, $logInfo->{pos}, $matchRegExp );
            if ( $isMatched == 1 ) {
                $isSuccess = 1;
            }
        }

        last if ( $isSuccess == 1 );
        sleep($step);
    }

    if ( $isSuccess == 0 ) {
        print("WARN: App url check failed.\n");
    }

    return $isSuccess;
}

#def copyDeployDesc(appname, appfilePath, targetdir, desctarget):
sub copyDeployDesc {
    my ( $appname, $appfilePath, $targetdir, $desctarget ) = @_;
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
            system("cp -p $dmgrtargetFile $pkgRoot/ && zip -qo $appname.ear $appfile");
        }
        elsif ( $appfilePath =~ /\.ear$/ ) {
            system("unzip -qo -d $appname.org.extract $dmgrtargetFile && unzip -qo -d $appname.extract $appfile");
            chdir("$appname.extract");
            my @jars = glob("*.jar");
            foreach my $jar (@jars) {
                system("unzip -qo -d $jar.extract $jar && cd $jar.extract && zip -qor ../../$appname.org.extract/$jar *");
            }

            chdir($pkgRoot);
            system("cd $appname.org.extract && zip -qor ../$appfile *.jar") if ( scalar(@jars) > 0 );
        }

        $cmd = "cp -p $appname.ear $dmgrtargetFile";
        print("INFO: $cmd\n");
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
            my $descdir = dirname($descdest);
            if ( not -d $descdir ) {
                mkpath($descdir);
            }
            if ( -f $descfile ) {
                File::Copy::cp( $descfile, $descdest );
                print("INFO: Update descriptor file:$descfile to $descdest\n");
            }
        }
    }
    chdir($curdir);
}

1;

