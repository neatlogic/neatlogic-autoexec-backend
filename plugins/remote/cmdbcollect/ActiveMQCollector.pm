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
use CollectObjType;

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

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $appInfo  = {};
    $appInfo->{OBJECT_TYPE} = $CollectObjType::APP;

    my $installPath;

    #获取-X的java扩展参数
    my ( $jmxPort,     $jmxSsl );
    my ( $minHeapSize, $maxHeapSize );
    my $jvmExtendOpts = '';
    my @cmdOpts = split( /\s+/, $procInfo->{COMMAND} );
    foreach my $cmdOpt (@cmdOpts) {
        if ( $cmdOpt =~ /^-Dcom\.sun\.management\.jmxremote\.port=(\d+)/ ) {
            $jmxPort = $1;
        }
        elsif ( $cmdOpt =~ /^-Dcom\.sun\.management\.jmxremote\.ssl=(\w+)\b/ ) {
            $jmxSsl = $1;
        }
        elsif ( $cmdOpt =~ /^-Xmx(\d+.*?)\b/ ) {
            $maxHeapSize = $1;
        }
        elsif ( $cmdOpt =~ /^-Xms(\d+.*?)\b/ ) {
            $minHeapSize = $1;
        }
        elsif ( $cmdOpt =~ /^-Dactivemq.home=(\S+)/ ) {
            $installPath              = $1;
            $appInfo->{ACTIVEMQ_HOME} = $installPath;
            $appInfo->{INSTALL_PATH}  = $installPath;
            $appInfo->{SERVER_NAME}   = basename($installPath);
        }
        elsif ( $cmdOpt =~ /^-Dactivemq.base=(\S+)/ ) {
            $appInfo->{ACTIVEMQ_BASE} = $1;
        }
        elsif ( $cmdOpt =~ /^-Dactivemq.conf(\S+)/ ) {
            $appInfo->{ACTIVEMQ_CONF} = $1;
            $appInfo->{CONFIG_PATH}   = $1;
        }
    }

    $appInfo->{MIN_HEAP_SIZE} = $minHeapSize + 0.0;
    $appInfo->{MAX_HEAP_SIZE} = $maxHeapSize + 0.0;
    $appInfo->{JMX_PORT}      = $jmxPort;
    $appInfo->{JMX_SSL}       = $jmxSsl;

    if ( not -e "$installPath/bin/activemq" ) {
        print("WARN: activemq not found in $installPath.\n");
        return undef;
    }

    my ( @ports, $proto, $port );

    #应用的安装目录并非一定是当前目录，TODO：需要补充更好的方法，
    #譬如：如果命令行启动命令是绝对路径，直接可以作为安装的路径的计算
    my $output = `$installPath/bin/activemq --version`;
    if ( $output =~ /ActiveMQ\s+(\d+\.\d+\.\d+)/ ) {
        my $version = $1;
        $appInfo->{VERSION} = $version;
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
                    $port  = $2;
                    if ( defined( $lsnPorts->{$port} ) ) {
                        $appInfo->{ uc("${proto}_PORT") } = $port;
                        push( @ports, $port );
                    }
                }
            }
        }
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
                    my $pt = $1;
                    if ( defined( $lsnPorts->{$pt} ) ) {
                        $mngtPort = $pt;
                    }
                }
            }
        }
    }
    $appInfo->{ADMIN_PORT}     = $mngtPort;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $mngtPort;

    $appInfo->{PORTS} = \@ports;
    if (@ports) {
        $appInfo->{PORT}     = $ports[0];
        $appInfo->{SSL_PORT} = $ports[0];
    }
    else {
        $appInfo->{PORT}     = undef;
        $appInfo->{SSL_PORT} = undef;
    }

    if ( defined($jmxPort) and $jmxPort ne '' ) {
        $appInfo->{MON_PORT} = $jmxPort;
    }

    return $appInfo;
}

1;
