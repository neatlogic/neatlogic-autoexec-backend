#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package MemcachedCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

sub getConfig {
    return {
        regExps  => ['\bmemcached\b'],          #正则表达是匹配ps输出
        psAttrs  => { COMM => 'memcached' },    #ps的属性的精确匹配
        envAttrs => {}                          #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $envMap           = $procInfo->{ENVIRONMENT};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $pid      = $procInfo->{PID};
    my $cmdLine  = $procInfo->{COMMAND};
    my $workPath = readlink("/proc/$pid/cwd");

    my $homePath;
    my $binPath;
    if ( $cmdLine =~ /^(.*?memcached)\s+-/ ) {
        $binPath = $1;
        $binPath =~ s/^["']|["']$//g;
        if ( $binPath =~ /^\.{1,2}[\/\\]/ ) {
            $binPath = "$workPath/$binPath";
        }
        $binPath  = Cwd::abs_path($binPath);
        $homePath = dirname($binPath);
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine not a lighttpd process.\n");
        return;
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{BIN_PATH}     = $binPath;
    $appInfo->{CONFIG_PATH}  = undef;

    $appInfo->{PORT}                 = undef;
    $appInfo->{UDP_PORT}             = undef;
    $appInfo->{MAX_CACHE_MEMORY}     = undef;
    $appInfo->{MAX_CONNECTION}       = undef;
    $appInfo->{THREAD_COUNT}         = undef;
    $appInfo->{BACKLOG}              = undef;
    $appInfo->{MAC_REQ_PER_EVENT}    = undef;
    $appInfo->{CHUNK_GROW_FACTOR}    = undef;
    $appInfo->{MIN_SPACE_PER_RECORD} = undef;

    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);
    $appInfo->{PORTS} = $ports;

    if ( defined($homePath) or $homePath ne '' ) {
        if ( $cmdLine =~ /\s-S\s/ ) {
            $appInfo->{SASL_ENABLED} = 1;
        }

        while ( $cmdLine =~ /(?<=\s)-(\w+)\s+([^-]+)/g ) {
            my $opt    = $1;
            my $optVal = $2;
            $optVal =~ s/^["']|["']$//g;
            if ( $opt eq 'p' ) {
                $port = int($optVal);
            }
            elsif ( $opt eq 'U' ) {
                if ( not defined($port) ) {
                    $port = int($optVal);
                }
                $appInfo->{UDP_PORT} = int($optVal);
            }
            elsif ( $opt eq 's' ) {

            }
            elsif ( $opt eq 'm' ) {
                $appInfo->{MAX_CACHE_MEMORY} = int($optVal);
            }
            elsif ( $opt eq 'c' ) {
                $appInfo->{MAX_CONNECTION} = int($optVal);
            }
            elsif ( $opt eq 't' ) {
                $appInfo->{THREAD_COUNT} = int($optVal);
            }
            elsif ( $opt eq 'b' ) {
                $appInfo->{BACKLOG} = int($optVal);
            }
            elsif ( $opt eq 'R' ) {
                $appInfo->{MAX_REQ_PER_EVENT} = int($optVal);
            }
            elsif ( $opt eq 'L' ) {
                $appInfo->{USE_LARGE_PAGE} = 1;
            }
            elsif ( $opt eq 'f' ) {
                $appInfo->{CHUNK_GROW_FACTOR} = $optVal + 0.0;
            }
            elsif ( $opt eq 'n' ) {
                $appInfo->{MIN_SPACE_PER_RECORD} = int($optVal);
            }
        }
    }

    if ( $port == 65535 ) {
        print("WARN: Can not determine Memcached listen port.\n");
        return undef;
    }

    $appInfo->{PORT} = $port;

    my $version;
    my $verInfo = $self->getCmdOut(qq{"$binPath" -h |head -n1});

    #memcached 1.4.15
    if ( $verInfo =~ /memcached\/([\d\.]+)/ ) {
        $version = $1;
    }
    $appInfo->{VERSION} = $version;

    $appInfo->{PORT}           = $port;
    $appInfo->{SSL_PORT}       = $port;
    $appInfo->{ADMIN_PORT}     = $port;
    $appInfo->{ADMIN_SSL_PORT} = $port;
    $appInfo->{MON_PORT}       = $port;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}

1;
