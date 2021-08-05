#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package ResinCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use XML::MyXML qw(xml_to_object);
use CollectObjType;

sub getConfig {
    return {
        regExps  => ['\bcom.caucho.server.resin.Resin\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                       #ps的属性的精确匹配
        envAttrs => {}                                        #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub getPK {
    my ($self) = @_;
    return {
        #默认KEY用类名去掉Collector，对应APP_TYPE属性值
        #配置值就是作为PK的属性名
        $self->{defaultAppType} => [ 'MGMT_IP', 'PORT' ]

            #如果返回的是多种对象，需要手写APP_TYPE对应的PK配置
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
    my $envMap           = $procInfo->{ENVRIONMENT};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{OBJECT_TYPE} = $CollectObjType::APP;

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $homePath;
    my $version;

    if ( $cmdLine =~ /-Dresin.home=(.*?)\s+-/ ) {
        $homePath = Cwd::abs_path($1);
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine not a jetty process.\n");
        return;
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{RESIN_HOME}   = $homePath;

    my $confFile;
    if ( $cmdLine =~ /-conf\s+(.*?)\s+-/ ) {
        $confFile = $1;
    }

    my $lsnMap = $procInfo->{CONN_INFO}->{LISTEN};
    my ( $port,    $sslPort );
    my ( $appAddr, $appPort, $appSslAddr, $appSslPort );
    my ( $webAddr, $webPort, $webSslAddr, $webSslPort );
    if ( -f $confFile ) {
        $appInfo->{CONFIG_PATH} = dirname($confFile);
        my $confObj = xml_to_object( $confFile, { file => 1 } );
        my @httpObjs = $confObj->path('cluster/server-default/http');
        foreach my $httpObj (@httpObjs) {
            if ( $httpObj->attr('port') and $httpObj->path('openssl') ) {
                $appSslPort = $httpObj->attr('port');
                $appSslAddr = $httpObj->attr('address');
            }
            elsif ( $httpObj->attr('port') ) {
                $appPort = $httpObj->attr('port');
                $appAddr = $httpObj->attr('address');
            }
        }

        @httpObjs = $confObj->path('resin:if/cluster/server-default/http');
        foreach my $httpObj (@httpObjs) {
            if ( $httpObj->attr('port') and $httpObj->path('openssl') ) {
                $webSslPort = $httpObj->attr('port');
                $webSslAddr = $httpObj->attr('address');
            }
            elsif ( $httpObj->attr('port') ) {
                $webPort = $httpObj->attr('port');
                $webAddr = $httpObj->attr('address');
            }
        }

        if ( defined($webPort) and ( defined( $lsnMap->{$webPort} ) or defined( $lsnMap->{"$webAddr:$webPort"} ) ) ) {
            $port = $webPort;
        }
        elsif ( defined($appPort) and ( defined( $lsnMap->{$appPort} ) or defined( $lsnMap->{"$appAddr:$appPort"} ) ) ) {
            $port = $appPort;
        }

        if ( defined($webSslPort) and ( defined( $lsnMap->{$webSslPort} ) or defined( $lsnMap->{"$webSslAddr:$webSslPort"} ) ) ) {
            $sslPort = $webSslPort;
        }
        elsif ( defined($appSslPort) and ( defined( $lsnMap->{$appSslPort} ) or defined( $lsnMap->{"$appSslAddr:$appSslPort"} ) ) ) {
            $sslPort = $appSslPort;
        }

        $appInfo->{PORT}     = $port;
        $appInfo->{SSL_PORT} = $sslPort;
    }
    else {
        $appInfo->{CONFIG_PATH} = undef;
    }

    my $javaHome;
    my $javaVersion;
    my $javaPath = readlink('/proc/$pid/exe');
    if ( not defined($javaPath) ) {
        $javaHome = $envMap->{JAVA_HOME};
        if ( defined($javaHome) ) {
            $javaPath = "$javaHome/bin/java";
        }
    }

    if ( defined($javaPath) ) {
        $javaHome = dirname($javaHome);
        my $javaVerInfo = $self->getCmdOut(qq{"$javaPath" -version 2>&1});
        if ( $javaVerInfo =~ /java version "(.*?)"/s ) {
            $javaVersion = $1;
        }
    }
    $appInfo->{JAVA_VERSION} = $javaVersion;
    $appInfo->{JAVA_HOME}    = $javaHome;

    # Resin-3.1.14 (built Mon, 28 Oct 2013 09:30:45 PDT)
    # Copyright(c) 1998-2008 Caucho Technology.  All rights reserved.
    my $version;
    my $verInfo = $self->getCmdOut("'$javaPath' -cp '$homePath/lib/resin.jar' com.caucho.Version");
    if ( $verInfo =~ /Resin-([\d\.]+)/ ) {
        $version = $1;
    }
    $appInfo->{VERSION} = $version;

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

    $appInfo->{MIN_HEAP_SIZE} = $utils->getMemSizeFromStr($minHeapSize);
    $appInfo->{MAX_HEAP_SIZE} = $utils->getMemSizeFromStr($maxHeapSize);
    $appInfo->{JMX_PORT}      = $jmxPort;
    $appInfo->{JMX_SSL}       = $jmxSsl;

    $appInfo->{ADMIN_PORT} = undef;

    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $jmxPort;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}
