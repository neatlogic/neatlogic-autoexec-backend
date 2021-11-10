#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package ApacheCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

sub getConfig {
    return {
        seq      => 100,
        regExps  => ['\bhttpd\s'],
        psAttrs  => { COMM => 'httpd' },
        envAttrs => {}
    };
}

sub getVerInfo {
    my ( $self, $cmd ) = @_;

    my $versionInfo     = {};
    my $apacheInfoLines = $self->getCmdOutLines($cmd);

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

    foreach my $line (@$apacheInfoLines) {
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
        my $fh    = IO::File->new("<$confFile");
        if ( defined($fh) ) {
            my $conf;
            $fh->read( $conf, $fSize );

            # <VitrualHost apache.quovadisglobal.com:443>
            # Listen 443
            # ServerName <your_server_name>:443
            # SSLEngine on
            # SSLCertificateFile /<path to <your_SSL_Certificate>.crt
            # SSLCertificateKeyFile /<path to the *.key file you created with the CSR>.key
            # SSLCertificateChainFile /<path to qv_bundle.crt>
            # </VirtualHost>
            # TODO：virtualhost的抽取没有经过测试
            my @virtualHosts;
            while ( $conf =~ s/\n\s*<\s*VitrualHost\s.*?\n<\/\s*VirtualHost\s*>//s ) {
                my $vConf       = $&;
                my $virtualHost = {};
                if ( $vConf =~ /\n\s*Listen\s+(\d+)\s*\n/s ) {
                    $virtualHost->{LISTEN} = $1;
                }
                if ( $vConf =~ /\n\s*ServerName\s+"(.+)"|^\s*ServerName\s+(.+)\n/s ) {
                    $virtualHost->{SERVER_NAME} = $1;
                }
                if ( $vConf =~ /\n\s*SSLEngine\s+on\s*\n/s ) {
                    $virtualHost->{SSL_ENGINE} = 'on';
                }
                else {
                    $virtualHost->{SSL_ENGINE} = 'off';
                }
                if ( $vConf =~ /\n\s*DocumentRoot\s+"(.+)"|^\s*DocumentRoot\s+(.+)\n/s ) {
                    $virtualHost->{DOCUMENT_ROOT} = $1;
                }
                push( @virtualHosts, $virtualHost );
            }

            $confInfo->{VIRTUAL_HOST} = \@virtualHosts;

            $confInfo->{SSL_ENGINE} = 'off';
            foreach my $line ( split( /\n/, $conf ) ) {
                ##Listen 12.34.56.78:80
                #Listen 80
                #ErrorLog "logs/error_log"
                #ServerRoot "/etc/httpd"
                #PidFile ""
                #ServerName www.example.com:80
                #DocumentRoot "/var/www/html"
                if ( $line =~ /^\s*SSLEngine\s+on\s*$/ ) {
                    $confInfo->{SSL_ENGINE} = 'on';
                }
                elsif ( $line =~ /^\s*Listen\s+(.+)$/i ) {
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

    $confInfo->{PORTS}      = \@listenPorts;
    $confInfo->{PORT}       = $listenPorts[0];
    $confInfo->{ADMIN_PORT} = $listenPorts[0];
    $confInfo->{MON_PORT}   = $listenPorts[0];

    if ( $confInfo->{SSL_ENGINE} eq 'on' ) {
        $confInfo->{SSL_PORT}       = $listenPorts[0];
        $confInfo->{ADMIN_SSL_PORT} = $listenPorts[0];
    }
    else {
        $confInfo->{SSL_PORT} = undef;
        $confInfo->{SSL_PORT} = undef;
    }

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
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $confPath;
    my $instPath;
    my $binPath;
    if ( $procInfo->{COMMAND} =~ /^\/usr\/sbin\/httpd\s+|^\/opt\/lampp\/bin\/httpd\s+/ ) {
        $binPath  = '/usr/sbin';
        $confPath = '/etc/httpd/conf';
        $instPath = '/etc/httpd';
    }
    else {
        if ( $procInfo->{COMMAND} =~ /^(.*?)\/httpd\s/ ) {
            $binPath = $1;
            if ( $binPath eq './' or $binPath eq '' ) {
                $binPath = $procInfo->{ENVRIONMENT}->{PWD};
            }
            $instPath = dirname($binPath);
            $confPath = "$instPath/conf";
        }
    }

    $appInfo->{INSTALL_PATH} = $instPath;
    $appInfo->{BIN_PATH}     = $binPath;
    $appInfo->{CONFIG_PATH}  = $confPath;

    my $verInfo = $self->getVerInfo(qq{"$binPath/httpd" -XV});
    if ( not defined( $verInfo->{VERSION} ) and -e "$binPath/apachectl" ) {
        $verInfo = $self->getVerInfo(qq{sh "$binPath/apachectl" -XV});
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
