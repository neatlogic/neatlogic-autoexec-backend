#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";

package LogTailer;

use strict;
use File::Copy;
use File::Path;
use File::Basename;
use IO::File;
use Cwd;
use IO::Socket::INET;
use HTTP::Tiny;

sub _tailLog {
    my ( $logInfo, $callback ) = @_;
    $| = 1;

    my $serverName = $logInfo->{server};
    my $logFile    = $logInfo->{path};
    my $pos        = $logInfo->{pos};
    my $logName    = $logInfo->{name};

    my $fh = IO::File->new("<$logFile");

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

        do {
            $line = $fh->getline();
            if ( defined($line) ) {
                print( $logName, ':', $line );

                if ( defined($callback) ) {
                    &$callback($line);
                }
            }
        } while ( defined($line) );

        $newPos = $fh->tell();
        $fh->close();
    }
    else {
        $newPos = 0;
        $logInfo->{pos} = 0;
        return -1;
    }

    $logInfo->{pos} = $newPos;
    return $newPos;
}

sub globPatterns {
    my ( $logPatterns, $logPaths, $logInfos ) = @_;

    foreach my $logPattern ( keys(%$logPatterns) ) {
        my @logFiles      = glob($logPattern);
        my $logFilesCount = scalar(@logFiles);

        #print("DEBUG: logPatterh:$logPattern, logFilesCount:$logFilesCount\n");
        if ( $logFilesCount > $logPatterns->{$logPattern} ) {
            $logPatterns->{$logPattern} = $logFilesCount;
            foreach my $logFile (@logFiles) {
                if ( not exists( $logPaths->{$logFile} ) ) {
                    $logPaths->{$logFile} = 1;

                    my $logInfo = {};
                    $logInfo->{server} = '';
                    $logInfo->{path}   = $logFile;
                    $logInfo->{name}   = basename($logFile);
                    $logInfo->{pos}    = 0;
                    my $fh = IO::File->new("<$logFile");
                    if ( defined($fh) ) {
                        push( @$logInfos, $logInfo );
                        print("INFO: Log file $logFile found.\n");
                        $fh->close();
                    }
                    else {
                        print("WARN: Read log file $logFile failed, $!\n");
                    }
                }
            }
        }
    }

}

sub _tailLogs {
    my ( $logInfos, $callback ) = @_;

    my $logPatterns = $$logInfos[0];
    my $logPaths    = $$logInfos[1];

    globPatterns( $logPatterns, $logPaths, $logInfos );

    my $logsCount = scalar(@$logInfos);
    for ( my $i = 2 ; $i < $logsCount ; $i++ ) {
        my $logInfo = $$logInfos[$i];
        my $newPos  = _tailLog( $logInfo, $callback );
    }
}

sub _checkUrl {
    my ( $url, $method, $timeout, $checkType, $loopNo ) = @_;
    my $isSuccess = 0;

    if ( not defined($method) or $method eq '' ) {
        $method = 'GET';
    }
    if ( not defined($timeout) or $timeout eq '' ) {
        $timeout = 300;
    }
    if ( not defined($url) or $url eq '' ) {
        print("ERROR: URL not defined.\n");
        return 0;
    }

    eval {
        my $statusCode = 500;

        my $http     = HTTP::Tiny->new( timeout => $timeout );
        my $response = $http->request( 'GET', $url );
        $statusCode = $response->{status};

        if ( $statusCode == 200 or $statusCode == 302 ) {
            if ( $loopNo % 10 == 0 and $checkType eq 'stop' ) {
                print("INFO: URL checking URL:$url, status code $statusCode, is up.\n");
            }

            if ( $checkType eq 'start' ) {
                print("INFO: URL checking URL:$url, status code $statusCode, is started.\n");
            }
            $isSuccess = 1;
        }
        else {
            if ( $loopNo % 10 == 0 and $checkType eq 'start' ) {
                print("INFO: URL checking URL:$url, status code $statusCode, is down.\n");
            }

            if ( $checkType eq 'stop' ) {
                print("INFO: URL checking URL:$url, status code $statusCode, is stopped.\n");
            }
        }
    };
    if ($@) {
        print("ERROR:$@\n");
    }

    return $isSuccess;
}

sub _checkTcp {
    my ( $host, $port, $timeout, $checkType, $loopNo ) = @_;

    my $isSuccess = 0;

    eval {
        my $socket = IO::Socket::INET->new(
            PeerHost => $host,
            PeerPort => int($port),
            Timeout  => $timeout
        );

        if ( defined($socket) ) {
            $isSuccess = 1;
            $socket->close();

            if ( $loopNo % 10 == 0 and $checkType eq 'stop' ) {
                print("INFO: $host:$port is listening.\n");
            }

            if ( $checkType eq 'start' ) {
                print("INFO: TCP checking:$host:$port is started.\n");
            }
        }
        else {
            if ( $loopNo % 10 == 0 and $checkType eq 'start' ) {
                print("INFO: $host:$port not connected.\n");
            }

            if ( $checkType eq 'stop' ) {
                print("INFO: TCP checking:$host:$port is stopped.\n");
            }
        }
    };
    if ($@) {
        print("ERROR:$@\n");
    }

    return $isSuccess;
}

sub _checkService {
    my ( $addrDef, $eofStr, $timeout, $logInfos, $upOrDown ) = @_;

    $| = 1;

    $addrDef =~ s/^\s*|\s*$//g;
    my @addrs         = split( /\s*[,;]\s*/, $addrDef );
    my $addrStatusMap = {};
    foreach my $addr (@addrs) {
        $addrStatusMap->{$addr} = $upOrDown ^ 1;
    }

    my $isSuccess = 0;
    my $step      = 3;
    my $stepCount = $timeout / $step;

    my $callback;
    if ( defined($eofStr) and $eofStr ne '' ) {
        $callback = sub {
            my ($line) = @_;
            if ( $line =~ /$eofStr/ ) {
                $isSuccess = $upOrDown;
            }
        };
    }

    _tailLogs( $logInfos, $callback );

    my $checkType;

    if ( $upOrDown == 1 ) {
        $checkType = 'start';
        print("INFO:waiting service to start....\n");
    }
    else {
        $checkType = 'stop';
        print("INFO:waiting service to stop....\n");
    }

    my $url;
    my $host;
    my $port;

    my $timeConsume = 0;
    my $startTime   = time();
    for ( my $i = 0 ; $i <= $stepCount ; $i++ ) {

        $isSuccess = $upOrDown;
        foreach my $addr (@addrs) {
            if ( $addrStatusMap->{$addr} == $upOrDown ) {
                next;
            }

            if ( index( $addr, 'http' ) >= 0 ) {
                $url = $addr;
                if ( _checkUrl( $url, 'GET', $step * 3, $checkType, $i ) != $upOrDown ) {
                    $isSuccess = $upOrDown ^ 1;
                    last;
                }
                else {
                    $addrStatusMap->{$addr} = $upOrDown;
                }
            }
            else {
                ( $host, $port ) = split( /\s*:\s*/, $addr );
                if ( _checkTcp( $host, $port, $step * 3, $checkType, $i ) != $upOrDown ) {
                    $isSuccess = $upOrDown ^ 1;
                    last;
                }
                else {
                    $addrStatusMap->{$addr} = $upOrDown;
                }
            }
        }

        _tailLogs( $logInfos, $callback );

        if ( $isSuccess == $upOrDown ) {
            last;
        }

        $timeConsume = time() - $startTime;
        if ( $timeConsume >= $timeout ) {
            print("WARN: Check timeout($timeout)\n");
            last;
        }

        sleep($step);
    }

    if ( $upOrDown == 1 ) {
        if ( $isSuccess == 0 ) {
            print("WARN: Service $addrDef is down.\n");
        }
        else {
            print("INFO: Service $addrDef is started.\n");
        }
    }
    else {
        if ( $isSuccess == 0 ) {
            print("INFO: Service $addrDef is stopped.\n");
        }
        else {
            print("WARN: Service $addrDef is up.\n");
        }
    }

    return $isSuccess;
}

sub checkUntilServiceUp {
    my ( $addrDef, $eofStr, $timeout, $logInfos ) = @_;
    return _checkService( $addrDef, $eofStr, $timeout, $logInfos, 1 );
}

sub checkUntilServiceDown {
    my ( $addrDef, $eofStr, $timeout, $logInfos ) = @_;
    return _checkService( $addrDef, $eofStr, $timeout, $logInfos, 0 );
}

sub checkEofstr {
    my ( $eofStr, $timeout, $logInfos ) = @_;

    $| = 1;

    my $isSuccess = 0;

    my $callback = sub {
        my ($line) = @_;
        if ( $line =~ /$eofStr/ ) {
            $isSuccess = 1;
        }
    };

    _tailLogs( $logInfos, $callback );

    my $step      = 3;
    my $stepCount = $timeout / $step;

    my $timeConsume = 0;
    my $startTime   = time();
    for ( my $i = 0 ; $i <= $stepCount ; $i++ ) {
        if ( $i % 10 == 0 ) {
            print("INFO:waiting for '$eofStr'....\n");
        }

        _tailLogs( $logInfos, $callback );

        if ( $isSuccess == 1 ) {
            last;
        }

        $timeConsume = time() - $startTime;
        if ( $timeConsume >= $timeout ) {
            print("WARN: Check timeout($timeout)\n");
            last;
        }

        sleep($step);
    }

    if ( $isSuccess == 0 ) {
        print("WARN:wait to get eof string:$eofStr timeout($timeout seconds).\n");
    }
    else {
        print("INFO: '$eofStr' matched.\n");
    }

    return $isSuccess;
}

1;

