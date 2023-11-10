#!/usr/bin/perl
use strict;

package CheckService;

use HTTP::Tiny;
use File::Copy;
use File::Path;
use File::Basename;
use IO::File;
use Cwd;

sub _checkTcp {
    my ( $host, $port, $keyword, $timeout ) = @_;

    my $isSuccess = 0;

    eval {
        print("INFO: Checking $host:$port...\n");
        my $socket = IO::Socket::INET->new(
            PeerHost => $host,
            PeerPort => $port,
            Timeout  => $timeout
        );

        if ( defined($socket) ) {
            $isSuccess = 1;
            print("INFO: Checking $host:$port success.\n");
            $socket->close();
        }
        else {
            print("INFO: Checking $host:$port failed, $!.\n");
        }

    };
    if ($@) {
        print("WARN: $@\n");
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
        # my $ua         = new LWP::UserAgent;
        # my $request    = HTTP::Request->new( "GET" => $url );
        # my $response   = $ua->request($request);

        my $http     = HTTP::Tiny->new( timeout => $timeout );
        my $response = $http->get($url);

        my $statusCode = $response->{status};

        #print("INFO: Checking $url, status code $statusCode\n");
        if ( $statusCode == 200 or $statusCode == 302 ) {
            if ( defined($keyword) ) {
                my $content = $response->content;
                if ( $content =~ /$keyword/i ) {
                    $isSuccess = 1;
                    print("INFO: Checking $url success.\n");
                }
            }
            else {
                $isSuccess = 1;
                print("INFO: Checking $url success.\n");
            }
        }
        else {
            my $reason = $response->{content};
            $reason =~ s/\s+$//;
            if ( length($reason) > 80 ) {
                $reason = $response->{reason};
            }
            print("INFO: Checking $url failed, $reason.\n");
        }
    };
    if ($@) {
        print("ERROR: $@\n");
    }

    return $isSuccess;
}

sub checkServiceAvailable {
    my ( $addrs, $keyword, $method, $timeout ) = @_;

    my $isSuccess    = 0;
    my $step         = 3;
    my $stepTimeout  = $step * 2;
    my $stepCount    = $timeout / $step;
    my $addrCheckMap = {};

    my $isTimeout = 0;
    my $startTime = time();
    for ( my $i = 0 ; $i < $stepCount ; $i++ ) {
        print("INFO: Waiting service to start....\n");

        my $allSuccess = 1;
        for my $addr (@$addrs) {
            if ( $addrCheckMap->{$addr} != 1 ) {
                if ( $addr =~ /^([\d\.]+):(\d+)$/ ) {
                    if ( _checkTcp( $1, $2, $keyword, $stepTimeout ) == 1 ) {
                        $addrCheckMap->{$addr} = 1;
                    }
                    else {
                        $allSuccess = 0;
                    }
                }
                else {
                    if ( _checkUrl( $addr, $keyword, $method, $stepTimeout ) == 1 ) {
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
        elsif ( time() - $startTime >= $timeout ) {
            $isTimeout = 1;
            print("WARN: Check service failed, imeout($timeout).\n");
            last;
        }

        sleep($step);
    }

    if ( $isSuccess == 0 ) {
        if ( $isTimeout == 0 and time() - $startTime >= $timeout ) {
            print("WARN: Check service failed, imeout($timeout).\n");
        }
        else {
            print("WARN: App service check failed. \n");
        }
    }
    else {
        print("INFO: Service started.\n");
    }

    return $isSuccess;
}

sub checkServiceDown {
    my ( $addrs, $method ) = @_;

    my $isDowned     = 0;
    my $addrCheckMap = {};

    print("INFO: Check if service is downed....\n");

    my $allDowned = 1;
    for my $addr (@$addrs) {
        if ( $addrCheckMap->{$addr} != 1 ) {
            if ( $addr =~ /^([\d\.]+):(\d+)$/ ) {
                if ( not _checkTcp( $1, $2, undef, 5 ) == 1 ) {
                    $addrCheckMap->{$addr} = 1;
                }
                else {
                    $allDowned = 0;
                }
            }
            else {
                if ( not _checkUrl( $addr, undef, $method, 5 ) == 1 ) {
                    $addrCheckMap->{$addr} = 1;
                }
                else {
                    $allDowned = 0;
                }
            }
        }
    }
    if ( $allDowned == 1 ) {
        $isDowned = 1;
        last;
    }

    if ( $isDowned == 1 ) {
        print("INFO: Service is downed.\n");
    }

    return $isDowned;
}

1;

