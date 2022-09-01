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
use CollectObjCat;

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
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $confPath;
    if ( $cmdLine =~ /-Dcatalina.base=(\S+)/ ) {
        $confPath = $1;
        $confPath =~ s/^["']|["']$//g;
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

            while ( $xml =~ /<\s*Connector\s[^>]*?\sSSLEnabled="true".*?>/isg ) {
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
            while ( $xml =~ /<\s*Connector\s[^>]*?\sprotocol=".*?http.*?>/isg ) {
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

            if ( not defined($port) ) {
                while ( $xml =~ /<\s*Connector\s[^>]*?>/isg ) {
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
            }

            if ( defined($port) ) {
                push( @ports, int($port) );
            }
            else {
                $port = $sslPort;
            }
            if ( defined($sslPort) ) {
                push( @ports, int($sslPort) );
            }
            $appInfo->{PORTS} = \@ports;

            if ( not defined($port) ) {
                print("WARN: Can not find Connector for port define in $confFile, failed.\n");
                return;
            }
            $appInfo->{PORT} = int($port);
            if ( defined($sslPort) ) {
                $appInfo->{SSL_PORT} = int($sslPort);
            }
        }
        else {
            print("WARN: Can not use file $confFile to detect listen port: $!\n");
        }
    }
    else {
        print("WARN: Can not fand catalina.base in command:$cmdLine, failed.\n");
        return;
    }

    my $installPath;
    if ( $cmdLine =~ /-Dcatalina.home=(\S+)\s+/ ) {
        $installPath = $1;
        $installPath =~ s/^["']|["']$//g;
        $appInfo->{CATALINA_HOME} = $installPath;
        $appInfo->{INSTALL_PATH}  = $installPath;
    }

    $self->getJavaAttrs($appInfo);
    my $javaHome = $appInfo->{JAVA_HOME};
    $appInfo->{MON_PORT} = $appInfo->{JMX_PORT};

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
    my $verCmd  = qq{JAVA_HOME="$javaHome" sh "$binPath/catalina.sh" version};
    if ( $procInfo->{OS_TYPE} eq 'Windows' ) {
        $ENV{JAVA_HOME} = $javaHome;
        $verCmd = qq{cmd /c "$binPath/catalina.bat" version};
    }
    my $verOut = $self->getCmdOutLines($verCmd);
    foreach my $line (@$verOut) {
        if ( $line =~ /Server number:\s*(.*?)\s*$/ ) {
            $appInfo->{VERSION} = $1;
        }
    }

    return $appInfo;
}

1;
