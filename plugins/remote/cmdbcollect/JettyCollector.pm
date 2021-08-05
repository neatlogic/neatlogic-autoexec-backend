#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package JettyCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

sub getConfig {
    return {
        regExps  => ['\b-Djetty.home=|start\.jar'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                #ps的属性的精确匹配
        envAttrs => {}                                 #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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
    my $basePath;
    my $version;

    $homePath = $envMap->{JETTY_HOME};
    if ( not defined($homePath) or $homePath eq '' ) {
        if ( $cmdLine =~ /-Djetty.home=(.*?)\s+-/ ) {
            $homePath = Cwd::abs_path($1);
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine not a jetty process.\n");
        return;
    }

    $basePath = $envMap->{JETTY_BASE};
    if ( not defined($basePath) or $basePath eq '' ) {
        if ( $cmdLine =~ /-Djetty.base=(.*?)\s+-/ ) {
            $basePath = Cwd::abs_path($1);
        }
    }
    if ( not defined($basePath) or $basePath eq '' ) {
        $basePath = $homePath;
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{JETTY_HOME}   = $homePath;
    $appInfo->{JETTY_BASE}   = $basePath;

    my $confPath = "$basePath/etc";
    if ( -d $confPath ) {
        $appInfo->{CONFIG_PATH} = $confPath;
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

    my $version = $self->getCmdOut("'$javaPath' -jar '$homePath/start.jar' --version | grep jetty-server | awk '{print \$2}'");
    $version =~ s/^\s*|\s*$//g;
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

    my $port;
    my $lsnPortsMap = $procInfo->{CONN_INFO}->{LISTEN};
    foreach my $lsnPortInfo ( keys(%$lsnPortsMap) ) {
        if ( $lsnPortInfo =~ /:(\d+)$/ or $lsnPortInfo =~ /^(\d+)$/ ) {
            my $lsnPort = $1;
            if ( $jmxPort ne $1 ) {
                $port = $lsnPort;
            }
        }
    }
    $appInfo->{PORT}       = $port;
    $appInfo->{ADMIN_PORT} = undef;

    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $jmxPort;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}
