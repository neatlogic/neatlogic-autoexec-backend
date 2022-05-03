#!/usr/bin/perl
use strict;

package checkService;

use LWP::UserAgent;
use File::Copy;
use File::Path;
use File::Basename;
use IO::File;
use Cwd;

sub _checkTcp {
    my ( $host, $port, $keyword, $timeout ) = @_;

    my $isSuccess = 0;

    eval {
        my $socket = IO::Socket::INET->new(
            PeerHost => $host,
            PeerPort => $port,
            Timeout  => $timeout
        );

        if ( defined($socket) ) {
            $isSuccess = 1;
            $socket->close();
        }

    };
    if ($@) {
        print("ERROR:$@\n");
    }

    return $isSuccess;
}

sub _checkUrl {
    my ( $url, $keyword, $method, $timeout ) = @_;
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
        my $ua         = new LWP::UserAgent;
        my $request    = HTTP::Request->new( "GET" => $url );
        my $response   = $ua->request($request);
        my $statusCode = $response->code;
        print("INFO:Checking $url, status code $statusCode\n");
        if ( $statusCode == 200 or $statusCode == 302 ) {
            if ( defined($keyword) ) {
                my $content = $response->content;
                if ( $content =~ /$keyword/i ) {
                    $isSuccess = 1;
                    print("INFO:Checking $url success.\n");
                }
            }
            else {
                $isSuccess = 1;
                print("INFO:Checking $url success.\n");
            }
        }
    };
    if ($@) {
        print("ERROR:$@\n");
    }

    return $isSuccess;
}

sub checkServiceAvailable {
    my ( $addrs, $keyword, $method, $timeout ) = @_;

    my $isSuccess    = 0;
    my $step         = 3;
    my $stepCount    = $timeout / $step;
    my $addrCheckMap = {};

    my $startTime = time();
    for ( my $i = 0 ; $i < $stepCount ; $i++ ) {
        print("INFO:waiting app to start....\n");

        my $allSuccess = 1;
        for my $addr (@$addrs) {
            if ( $addrCheckMap->{$addr} != 1 ) {
                if ( $addr =~ /^([\d\.]+):(\d+)$/ ) {
                    if ( _checkTcp( $1, $2, $keyword, $timeout ) == 1 ) {
                        $addrCheckMap->{$addr} = 1;
                    }
                    else {
                        $allSuccess = 0;
                    }
                }
                else {
                    if ( _checkUrl( $addr, $keyword, $method, $timeout ) == 1 ) {
                        $addrCheckMap->{$addr} = 1;
                    }
                    else {
                        $allSuccess = 0;
                    }
                }
            }
        }
        if ( $allSuccess == 1 ) {
            $isSuccess = 1;
            last;
        }

        if ( time() - $startTime > $timeout ) {
            print("WARN: Check service imeout($timeout).\n");
        }

        sleep($step);
    }

    if ( $isSuccess == 0 ) {
        print("WARN:App service check failed. \n");
    }

    return $isSuccess;
}

1;

