#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package APACHECollector;

use strict;
use parent 'BASECollector';

use File::Basename;

sub getVerInfo {
    my ( $self, $cmd ) = @_;

    my $versionInfo = {};
    my @apacheInfos = `$cmd`;

    #httpd -V或apachectl -V的输出
    # Server version: Apache/2.4.34 (Unix)
    # Server built:   Feb 22 2019 20:20:11
    # Server's Module Magic Number: 20120211:79
    # Server loaded:  APR 1.5.2, APR-UTIL 1.5.4
    # Compiled using: APR 1.5.2, APR-UTIL 1.5.4
    # Architecture:   64-bit
    # Server MPM:     prefork
    #   threaded:     no
    #     forked:     yes (variable process count)
    # Server compiled with....
    #  -D APR_HAS_SENDFILE
    #  -D APR_HAS_MMAP
    #  -D APR_HAVE_IPV6 (IPv4-mapped addresses enabled)
    #  -D APR_USE_FLOCK_SERIALIZE
    #  -D APR_USE_PTHREAD_SERIALIZE
    #  -D SINGLE_LISTEN_UNSERIALIZED_ACCEPT
    #  -D APR_HAS_OTHER_CHILD
    #  -D AP_HAVE_RELIABLE_PIPED_LOGS
    #  -D DYNAMIC_MODULE_LIMIT=256
    #  -D HTTPD_ROOT="/usr"
    #  -D SUEXEC_BIN="/usr/bin/suexec"
    #  -D DEFAULT_PIDLOG="/private/var/run/httpd.pid"
    #  -D DEFAULT_SCOREBOARD="logs/apache_runtime_status"
    #  -D DEFAULT_ERRORLOG="logs/error_log"
    #  -D AP_TYPES_CONFIG_FILE="/private/etc/apache2/mime.types"
    #  -D SERVER_CONFIG_FILE="/private/etc/apache2/httpd.conf"

    foreach my $line (@apacheInfos) {
        if ( $line =~ /Server version:\s+(.*?)$/ ) {
            $versionInfo->{VERSION} = $1;
        }
        elsif ( $line =~ /Server MPM:\s+(.*?)$/ ) {
            $versionInfo->{SERVER_MPM} = $1;
        }
        elsif ( $line =~ /HTTPD_ROOT="(.*?)"/ ) {
            $versionInfo->{HTTPD_ROOT} = $1;
        }
        elsif ( $line =~ /DEFAULT_PIDLOG="(.*?)"/ ) {
            $versionInfo->{DEFAULT_PIDLOG} = $1;
        }
        elsif ( $line =~ /DEFAULT_ERRORLOG="(.*?)"/ ) {
            $versionInfo->{DEFAULT_ERRORLOG} = $1;
        }
        elsif ( $line =~ /AP_TYPES_CONFIG_FILE="(.*?)"/ ) {
            $versionInfo->{AP_TYPES_CONFIG_FILE} = $1;
        }
        elsif ( $line =~ /SERVER_CONFIG_FILE="(.*?)"/ ) {
            $versionInfo->{SERVER_CONFIG_FILE} = $1;
        }
    }

    return $versionInfo;
}

sub getConfInfo {
    my ( $self, $confFile ) = @_;

    my $confInfo = {};

    my @listenPorts = ();
    if ( -e $confFile ) {
        my $fSize = -s $confFile;
        my $fh    = IO::File->new("<confFile");

        if ( defined($fh) ) {
            my $line;
            while ( $line = <$fh> ) {
                ##Listen 12.34.56.78:80
                #Listen 80
                #ErrorLog "logs/error_log"
                #ServerRoot "/etc/httpd"
                #PidFile ""
                #ServerName www.example.com:80
                #DocumentRoot "/var/www/html"
                if ( $line =~ /^\s*Listen\s+(.+)$/i ) {
                    push( @listenPorts, $1 );
                }
                elsif ( $line =~ /^\s*ErrorLog\s+"(.+)"|^\s*ErrorLog\s+(.+)$/i ) {
                    $confInfo->{ERRORLOG} = $1;
                }
                elsif ( $line =~ /^\s*ServerRoot\s+"(.+)"|^\s*ServerRoot\s+(.+)$/i ) {
                    $confInfo->{SERVER_ROOT} = $1;
                }
                elsif ( $line =~ /^\s*PidFile\s+"(.+)"|^\s*PidFile\s+(.+)$/i ) {
                    $confInfo->{PID_FILE} = $1;
                }
                elsif ( $line =~ /^\s*ServerName\s+"(.+)"|^\s*ServerName\s+(.+)$/i ) {
                    $confInfo->{SERVER_NAME} = $1;
                }
                elsif ( $line =~ /^\s*DocumentRoot\s+"(.+)"|^\s*DocumentRoot\s+(.+)$/i ) {
                    $confInfo->{DOCUMENT_ROOT} = $1;
                }
            }
            $fh->close();
        }
    }

    $confInfo->{PORTS} = \@listenPorts;
    $confInfo->{PORT}  = $listenPorts[0];

    return $confInfo;
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};

    if ( $procInfo->{COMM} ne 'httpd' ) {
        return undef;
    }

    my $appInfo = {};

    my $confPath;
    my $instPath;
    my $binPath;
    if ( $procInfo->{COMMAND} =~ /^\/usr\/sbin\/httpd\s+|^\/opt\/lampp\/bin\/httpd\s+/ ) {
        $binPath  = '/usr/sbin/';
        $confPath = '/etc/httpd/conf';
        $instPath = '/etc/httpd';
    }
    else {
        if ( $procInfo->{COMMAND} =~ /^(.*?)\/httpd\s/ ) {
            $binPath = $1;
            if ( $binPath eq './' or $binPath eq '' ) {
                $binPath = $procInfo->{ENVRIONMENT}->{CWD};
            }
            $instPath = dirname($binPath);
            $confPath = "$instPath/conf";
        }
    }

    $appInfo->{INSTALL_PATH} = $instPath;
    $appInfo->{BIN_PATH}     = $binPath;
    $appInfo->{CONF_PATH}    = $confPath;

    my $verInfo = $self->getVerInfo("$binPath/httpd -XV");
    if ( not defined( $verInfo->{VERSION} ) and -x "$binPath/apachectl" ) {
        $verInfo = $self->getVerInfo("$binPath/apachectl -XV");
    }
    while ( my ( $k, $v ) = each(%$verInfo) ) {
        $appInfo->{$k} = $v;
    }

    my $confFile = "$confPath/httpd.conf";
    my $confInfo = $self->getConfInfo($confFile);
    while ( my ( $k, $v ) = each(%$confInfo) ) {
        $appInfo->{$k} = $v;
    }

    #TODO: 多监听的情况怎么处理，原来是有一instances的记录，需确认
    return $appInfo;
}

1;
