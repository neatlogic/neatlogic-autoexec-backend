#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package TomcatCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;

sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\borg.apache.catalina.startup.Bootstrap\s'],
        psAttrs  => { COMM => 'java' },
        envAttrs => {}
    };
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $appInfo  = {};

    my $confPath;
    if ( $procInfo->{COMMAND} =~ /-Dcatalina.base=(\S+)\s+/ ) {
        $confPath                 = $1;
        $appInfo->{CATALINA_BASE} = $confPath;
        $appInfo->{CONFIG_PATH}   = $confPath;
        $appInfo->{SERVER_NAME}  = basename($confPath);

        my $confFile = "$confPath/conf/server.xml";
        my $fh       = IO::File->new("<$confFile");
        if ( defined($fh) ) {
            my $fSize = -s $confFile;
            my $xml;
            $fh->read( $xml, $fSize );

            my $lsnPorts = $procInfo->{CONN_INFO}->{LISTEN};

            my @ports = ();
            my ( $port, $sslPort );

            while ( $xml =~ /<\s*Connector\s[^>]+?\sSSLEnabled="true"\s.*?>/sg ) {
                my $matchContent = $&;
                if ( $matchContent =~ /port="(.*?)"/ ) {
                    $sslPort = $1;
                    if ( $sslPort =~ /\$\{(.*?)\}/ ) {
                        my $optName = $1;
                        if ( $procInfo->{COMMAND} =~ /-D$optName=(\d+)/ ) {
                            $sslPort = $1;
                        }
                    }
                    if ( not defined( $lsnPorts->{$sslPort} ) ) {
                        undef($sslPort);
                    }
                    else {
                        last;
                    }
                }
            }

            pos($xml) = 0;    #从头开始匹配
            while ( $xml =~ /<\s*Connector\s[^>]+?\sprotocol="HTTP\b.*?>/sg ) {
                my $matchContent = $&;
                if ( $matchContent =~ /port="(.*?)"/ ) {
                    $port = $1;
                    if ( $port =~ /\$\{(.*?)\}/ ) {
                        my $optName = $1;
                        if ( $procInfo->{COMMAND} =~ /-D$optName=(\d+)/ ) {
                            $port = $1;
                        }
                    }

                    if ( not defined( $lsnPorts->{$port} ) ) {
                        undef($port);
                    }
                    else {
                        last;
                    }
                }
            }

            $appInfo->{PORT}     = $port;
            $appInfo->{SSL_PORT} = $sslPort;
            if ( defined($port) ) {
                push( @ports, $port );
            }
            if ( defined($sslPort) ) {
                push( @ports, $sslPort );
            }
            $appInfo->{PORTS} = \@ports;
        }
    }
    else {
        $appInfo->{SERVER_NAME} = 'tomcat';
    }

    my $installPath;
    if ( $procInfo->{COMMAND} =~ /-Dcatalina.home=(\S+)\s+/ ) {
        $installPath              = $1;
        $appInfo->{CATALINA_HOME} = $installPath;
        $appInfo->{INSTALL_PATH}  = $installPath;
    }

    #Using CATALINA_BASE:   /app/servers/balantflow
    #Using CATALINA_HOME:   /app/servers/balantflow
    #Using CATALINA_TMPDIR: /app/servers/balantflow/temp
    #Using JRE_HOME:        /app/serverware/jdk
    #Using CLASSPATH:       /app/servers/balantflow/bin/bootstrap.jar:/app/servers/balantflow/bin/tomcat-juli.jar
    #Using CATALINA_OPTS:
    #Server version: Apache Tomcat/9.0.44
    #Server built:   Mar 4 2021 21:49:34 UTC
    #Server number:  9.0.44.0
    #OS Name:        Linux
    #OS Version:     3.10.0-514.el7.x86_64
    #Architecture:   amd64
    #JVM Version:    1.8.0_77-b03
    #JVM Vendor:     Oracle Corporation
    my $binPath = "$installPath/bin";
    my $verCmd  = "sh $binPath/version.sh";
    if ( $procInfo->{OS_TYPE} eq 'Windows' ) {
        $verCmd = `cmd /c $binPath/version.bat`;
    }
    my @verOut = `$verCmd`;
    foreach my $line (@verOut) {
        if ( $line =~ /Server number:\s*(.*?)\s*$/ ) {
            $appInfo->{VERSION} = $1;
        }
        elsif ( $line =~ /JVM Vendor:\s*(.*?)\s*$/ ) {
            $appInfo->{JVM_VENDER} = $1;
        }
        elsif ( $line =~ /JRE_HOME:\s*(.*?)\s*$/ ) {
            $appInfo->{JRE_HOME} = $1;
        }
        elsif ( $line =~ /JVM Version:\s*(.*?)\s*$/ ) {
            $appInfo->{JVM_VERSION} = $1;
        }
    }

    #获取-X的java扩展参数
    my ( $jmxPort,     $jmxSsl );
    my ( $minHeapSize, $maxHeapSize );
    my $jvmExtendOpts = '';
    my @cmdOpts = split( /\s+/, $procInfo->{COMMAND} );
    foreach my $cmdOpt (@cmdOpts) {
        if ( $cmdOpt =~ /-Dcom\.sun\.management\.jmxremote\.port=(\d+)/ ) {
            $jmxPort = $1;
        }
        elsif ( $cmdOpt =~ /-Dcom\.sun\.management\.jmxremote\.ssl=(\w+)\b/ ) {
            $jmxSsl = $1;
        }
        elsif ( $cmdOpt =~ /^-Xmx(\d+.*?)\b/ ) {
            $maxHeapSize = $1;
        }
        elsif ( $cmdOpt =~ /^-Xms(\d+.*?)\b/ ) {
            $minHeapSize = $1;
        }
    }

    $appInfo->{MIN_HEAP_SIZE} = $minHeapSize;
    $appInfo->{MAX_HEAP_SIZE} = $maxHeapSize;
    $appInfo->{JMX_PORT}      = $jmxPort;
    $appInfo->{JMX_SSL}       = $jmxSsl;
    $appInfo->{MON_PORT}      = $jmxPort;

    return $appInfo;
}

1;
