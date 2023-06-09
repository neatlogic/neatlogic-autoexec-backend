#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package ActiveMQCollector;

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
        regExps  => ['\s-Dactivemq.home='],
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
    my $appInfo  = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $installPath;

    my @cmdOpts = split( /\s+/, $procInfo->{COMMAND} );
    foreach my $cmdOpt (@cmdOpts) {
        if ( $cmdOpt =~ /^-Dactivemq.home=(\S+)/ ) {
            $installPath              = $1;
            $appInfo->{ACTIVEMQ_HOME} = $installPath;
            $appInfo->{INSTALL_PATH}  = $installPath;
            $appInfo->{SERVER_NAME}   = basename($installPath);
        }
        elsif ( $cmdOpt =~ /^-Dactivemq.base=(\S+)/ ) {
            $appInfo->{ACTIVEMQ_BASE} = $1;
        }
        elsif ( $cmdOpt =~ /^-Dactivemq.conf=(\S+)/ ) {
            $appInfo->{ACTIVEMQ_CONF} = $1;
            $appInfo->{CONFIG_PATH}   = $1;
        }
        elsif ( $cmdOpt =~ /^-Dactivemq.data=(\S+)/ ) {
            $appInfo->{ACTIVEMQ_DATA_PATH} = $1;
        }
    }

    $self->getJavaAttrs($appInfo);
    my $javaHome = $appInfo->{JAVA_HOME};

    if ( not -e "$installPath/bin/activemq" ) {
        print("WARN: Activemq not found in $installPath.\n");
        return undef;
    }

    #应用的安装目录并非一定是当前目录，TODO：需要补充更好的方法，
    #譬如：如果命令行启动命令是绝对路径，直接可以作为安装的路径的计算
    my $output = $self->getCmdOut(qq{JAVA_HOME="$javaHome" sh "$installPath/bin/activemq" --version});
    if ( $output =~ /ActiveMQ\s+(\d+\.\d+\.\d+)/ ) {
        my $version = $1;
        $appInfo->{VERSION} = $version;
        if ( $version =~ /(\d+)/ ) {
            $appInfo->{MAJOR_VERSION} = "ActiveMQ$1";
        }
    }

    #         <transportConnectors>
    #             <!-- DOS protection, limit concurrent connections to 1000 and frame size to 100MB -->
    #             <transportConnector name="openwire" uri="tcp://0.0.0.0:61616?maximumConnections=1000&amp;transport.keepAlive=true" enab
    # leStatusMonitor="true"/>
    # <!--
    #             <transportConnector name="amqp" uri="amqp://0.0.0.0:5672?maximumConnections=1000&amp;wireFormat.maxFrameSize=104857600"/>
    #             <transportConnector name="stomp" uri="stomp://0.0.0.0:61613?maximumConnections=1000&amp;wireFormat.maxFrameSize=104857600"/>
    #             <transportConnector name="mqtt" uri="mqtt://0.0.0.0:1883?maximumConnections=1000&amp;wireFormat.maxFrameSize=104857600"/>
    #             <transportConnector name="ws" uri="ws://0.0.0.0:61614?maximumConnections=1000&amp;wireFormat.maxFrameSize=104857600"/>
    # -->
    #         </transportConnectors>

    my $servicePorts = $appInfo->{SERVICE_PORTS};
    if ( not defined($servicePorts) ) {
        $servicePorts = {};
        $appInfo->{SERVICE_PORTS} = $servicePorts;
    }

    my $ports = [];
    my $port;
    my $proto;
    my $minPort  = 65535;
    my $lsnPorts = $procInfo->{CONN_INFO}->{LISTEN};
    my $confFile = "$installPath/conf/activemq.xml";
    if ( -e $confFile ) {
        my $fSize = -s $confFile;
        my $fh    = IO::File->new("<$confFile");
        if ( defined($fh) ) {
            my $xml;
            $fh->read( $xml, $fSize );

            if ( $xml =~ /<\s*transportConnectors\s*>.*?<\/\s*transportConnectors\s*>/s ) {
                my $connectorsContent = $&;
                while ( $connectorsContent =~ /<\s*transportConnector name="(\w+)" .*?:(\d+)/sg ) {
                    $proto = $1;
                    $port  = int($2);
                    if ( defined( $lsnPorts->{$port} ) ) {
                        $servicePorts->{ lc($proto) } = $port;
                        push( @$ports, $port );

                        if ( $port < $minPort ) {
                            $minPort = $port;
                        }
                    }
                }
            }
        }
    }
    if ( $minPort < 65535 ) {
        $port = $minPort;
    }
    else {
        ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);
    }

    if ( $port == 65535 ) {
        print("WARN: Can not determine ActiveMQ listen port.\n");
        return undef;
    }

    my $mngtPort;
    my $jettFile = "$installPath/conf/jetty.xml";
    if ( -e $jettFile ) {
        my $fSize = -s $jettFile;
        my $fh    = IO::File->new("<$jettFile");
        if ( defined($fh) ) {
            my $xml;
            $fh->read( $xml, $fSize );
            while ( $xml =~ /<property\s.*?name="port".*?\/>/sg ) {
                my $portDef = $&;
                if ( $portDef =~ /value="(\d+)"/ ) {
                    my $pt = int($1);
                    if ( defined( $lsnPorts->{$pt} ) ) {
                        $mngtPort = $pt;
                        $servicePorts->{admin} = $mngtPort;
                    }
                }
            }
        }
    }

    $appInfo->{ADMIN_PORT}     = $mngtPort;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    $appInfo->{PORT}     = $port;
    $appInfo->{SSL_PORT} = undef;

    return $appInfo;
}

1;
