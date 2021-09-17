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
use CollectObjType;

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
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $cmdLine  = $procInfo->{COMMAND};
    my $appInfo  = {};
    $appInfo->{OBJECT_TYPE} = $CollectObjType::APP;

    my $confPath;
    if ( $cmdLine =~ /-Dcatalina.base=(\S+)/ ) {
        $confPath                 = $1;
        $appInfo->{CATALINA_BASE} = $confPath;
        $appInfo->{CONFIG_PATH}   = $confPath;
        $appInfo->{SERVER_NAME}   = basename($confPath);

        my $confFile = "$confPath/conf/server.xml";
        my $fh       = IO::File->new("<$confFile");
        if ( defined($fh) ) {
            my $fSize = -s $confFile;
            my $xml;
            $fh->read( $xml, $fSize );

            my $lsnPortsMap = $procInfo->{CONN_INFO}->{LISTEN};

            my @ports = ();
            my ( $port, $sslPort );

            while ( $xml =~ /<\s*Connector\s[^>]+?\sSSLEnabled="true"\s.*?>/sg ) {
                my $matchContent = $&;
                if ( $matchContent =~ /port="(.*?)"/ ) {
                    $sslPort = $1;
                    if ( $sslPort =~ /\$\{(.*?)\}/ ) {
                        my $optName = $1;
                        if ( $cmdLine =~ /-D$optName=(\d+)/ ) {
                            $sslPort = $1;
                        }
                    }
                    if ( not defined( $lsnPortsMap->{$sslPort} ) ) {
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
                        if ( $cmdLine =~ /-D$optName=(\d+)/ ) {
                            $port = $1;
                        }
                    }

                    if ( not defined( $lsnPortsMap->{$port} ) ) {
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
        print("WARN: Can not fand catalina.base in command:$cmdLine, failed.\n");
        return;
    }

    my $installPath;
    if ( $cmdLine =~ /-Dcatalina.home=(\S+)\s+/ ) {
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
    my $verCmd  = qq{sh "$binPath/catalina.sh" version};
    if ( $procInfo->{OS_TYPE} eq 'Windows' ) {
        $verCmd = qq{cmd /c "$binPath/catalina.bat" version};
    }
    my @verOut = $self->getCmdOut($verCmd);
    foreach my $line (@verOut) {
        if ( $line =~ /Server number:\s*(.*?)\s*$/ ) {
            $appInfo->{VERSION} = $1;
        }
    }

    $self->getJavaAttrs($appInfo);

    $appInfo->{MON_PORT} = $appInfo->{JMX_PORT};

    return $appInfo;
}

1;
