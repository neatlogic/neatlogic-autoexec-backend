#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package JBossCollector;

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
        regExps  => ['jboss'],
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
    my $envMap   = $procInfo->{ENVRIONMENT};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $homePath;
    my $installPath;
    if ( $cmdLine =~ /-Djboss\.home\.dir=(\S+)\s+/ ) {
        $homePath    = $1;
        $installPath = $homePath;
    }
    elsif ( defined( $envMap->{JBOSS_HOME} ) ) {
        $installPath = $envMap->{JBOSS_HOME};
    }
    else {
        return;
    }
    $appInfo->{JBOSS_HOME}   = $installPath;
    $appInfo->{INSTALL_PATH} = $installPath;

    my $ip;
    if ( $cmdLine =~ /-Djboss\.bind\.address=(\d+\.\d+\.\d+\.\d+)/ ) {
        $ip = $1;
    }
    elsif ( $cmdLine =~ /-b\s(\d+\.\d+\.\d+\.\d+)/ ) {
        $ip = $1;
    }
    if ( defined($ip) ) {
        $appInfo->{IP} = $ip;
    }
    else {
        $appInfo->{IP} = $procInfo->{MGMT_IP};
    }

    my $runMode;
    if ( $cmdLine =~ /-D\[Standalone/ ) {
        $runMode = 'Standalone';
    }
    elsif ( $cmdLine =~ /-D\[Server/ ) {
        $runMode = 'Server';
    }
    $appInfo->{RUN_MODE} = $runMode;

    my $binPath = "$installPath/bin";
    my $verScript;
    if ( $procInfo->{OS_TYPE} eq 'Windows' ) {
        if ( -e "$binPath/domain.bat" ) {
            $verScript = "domain.bat";
        }
        elsif ( -e "$binPath/standalone.bat" ) {
            $verScript = "standalone.bat";
        }
        else {
            $verScript = "run.bat";
        }
    }
    else {
        if ( -e "$binPath/domain.sh" ) {
            $verScript = "domain.sh";
        }
        elsif ( -e "$binPath/standalone.sh" ) {
            $verScript = "standalone.sh";
        }
        else {
            $verScript = "run.sh";
        }
    }

    my $verCmd = qq{sh "$binPath/$verScript" --version};
    my @verOut = $self->getCmdOut($verCmd);
    foreach my $line (@verOut) {
        if ( $line =~ /jboss ([a-z]+\s)?(\d[^\s]*)/ ) {
            $appInfo->{VERSION} = "$1$2";
        }
    }

    my $confPath;
    if ( $cmdLine =~ /-Djboss\.server\.base\.dir=(\S+)\s+/ ) {
        $confPath               = $1;
        $appInfo->{JBOSS_BASE}  = $confPath;
        $appInfo->{CONFIG_PATH} = $confPath;
        $appInfo->{SERVER_NAME} = basename($confPath);

        my $lsnPorts = $procInfo->{CONN_INFO}->{LISTEN};
        my @ports    = ();
        my ( $port, $sslPort );

        if ( $runMode eq 'Server' ) {
            my @portOffsets = (0);
            if ( $cmdLine =~ /-Djboss\.socket\.binding\.port-offset=(\d+)/ ) {
                push( @portOffsets, int($1) );
            }

            my $hostConf;
            if ( $cmdLine =~ /-Djboss\.host\.default\.config=(\S+)/ ) {
                $hostConf = $1;
            }
            else {
                $hostConf = 'host.xml';
            }
            my $hostXml = $utils->getFileContent("$confPath/configuration/$hostConf");

            my $domainConf;
            if ( $cmdLine =~ /-Djboss\.domain\.default\.config=(\S+)/ ) {
                $domainConf = $1;
            }
            else {
                $domainConf = "domain.xml";
            }
            my $domainXml = $utils->getFileContent("$confPath/configuration/$domainConf");

            while ( $hostXml =~ /port-offset\s*?=\s*?"[^\"]*?(\d+)/sg ) {
                push( @portOffsets, int($1) );
            }

            while ( $domainXml =~ /<socket-binding[^>]*?name\s*?=\s*?"http"[^>]?port\s*?=\s*?"(\d+)"/sg ) {
                $port = $1;
                foreach my $offset (@portOffsets) {
                    if ( defined( $lsnPorts->{ $port + $offset } ) ) {
                        $port = $port + $offset;
                        last;
                    }
                }
                undef($port);
            }
        }
        elsif ( $runMode eq 'Standalone' ) {
            my @portOffsets = (0);
            if ( $cmdLine =~ /-Djboss\.socket\.binding\.port-offset=(\d+)/ ) {
                push( @portOffsets, int($1) );
            }

            my $hostConf;
            if ( $cmdLine =~ /-Djboss.server.default.config=(\S+)/ ) {
                $hostConf = $1;
            }
            elsif ( $cmdLine =~ /--server-config=(\S+)/ ) {
                $hostConf = $1;
            }
            else {
                $hostConf = 'standalone.xml';
            }
            my $hostXml = $utils->getFileContent("$confPath/configuration/$hostConf");

            while ( $hostXml =~ /port-offset\s*?=\s*?"[^\"]*?(\d+)/sg ) {
                push( @portOffsets, int($1) );
            }

            pos($hostXml) = 0;
            while ( $hostXml =~ /<socket-binding[^>]*?name\s*?=\s*?"http"[^>]?port\s*?=\s*?"(\d+)"/sg ) {
                $port = $1;
                foreach my $offset (@portOffsets) {
                    if ( defined( $lsnPorts->{ $port + $offset } ) ) {
                        $port = $port + $offset;
                        last;
                    }
                }
                undef($port);
            }
        }
        else {
            if ( $cmdLine =~ /-c\s+(\S+)/ ) {
                $runMode = $1;
            }
            else {
                $runMode = 'default';
            }

            my @possiblePorts = ();

            my $portXmlPath;
            my $xml = $utils->getFileContent("$homePath/server/$runMode/conf/jboss-service.xml");
            while ( $xml =~ /<mbean.*?code="org.jboss.services.binding.ServiceBindingManager".*?<attribute.*?name="StoreURL".*?>(.*?)<\/attribute>.*?<\/mbean>/sg ) {
                $portXmlPath = $1;
                $portXmlPath =~ s/\$\{jboss\.home\.url\}/$homePath/g;
            }

            if ( defined($portXmlPath) ) {
                my $portXml = $self->getFileContent($portXmlPath);
                while ( $portXml =~ /connector.*?port="(\d+)".*?protocol=".*?http.*?"/sg ) {
                    push( @possiblePorts, $1 );
                }
            }
            else {
                my $portXml = $self->getFileContent("$homePath/server/$runMode/deploy//jboss-web.deployer/server.xml");
                while ( $portXml =~ /connector.*?port="(\d+)".*?protocol=".*?http.*?"/sg ) {
                    push( @possiblePorts, $1 );
                }
            }
            foreach my $possiblePort (@possiblePorts) {
                if ( defined( $lsnPorts->{$possiblePort} ) ) {
                    $port = $possiblePort;
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
    else {
        print("WARN: Can not fand catalina.base in command:$cmdLine, failed.\n");
        return;
    }

    $self->getJavaAttrs($appInfo);

    $appInfo->{MON_PORT} = $appInfo->{JMX_PORT};

    return $appInfo;
}

1;
