#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package ElasticsearchCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use YAML::Tiny;
use CollectObjType;

sub getConfig {
    return {
        regExps  => ['\borg.elasticsearch.bootstrap.Elasticsearch\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                                   #ps的属性的精确匹配
        envAttrs => {}                                                    #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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

    my $user     = $procInfo->{USER};
    my $workPath = readlink("/proc/$pid/cwd");

    #-Des.path.home=/opt/elasticsearch-7.5.1 -Des.path.conf=/opt/elasticsearch-7.5.1/config -Des.distribution.flavor=oss
    my $homePath;
    my $confPath;

    if ( $cmdLine =~ /\s-Des.path.home=(.*?)\s+-/ ) {
        $homePath = $1;
        if ( $homePath =~ /^\.{1,2}[\/\\]/ ) {
            $homePath = "$workPath/$homePath";
        }
        $homePath = Cwd::abs_path($homePath);
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine not a elasticsearch process.\n");
        return;
    }

    if ( $cmdLine =~ /\s-Des.path.conf=(.*?)\s+-/ ) {
        $confPath = $1;
        if ( $confPath =~ /^\.{1,2}[\/\\]/ ) {
            $confPath = "$workPath/$confPath";
        }
        $confPath = Cwd::abs_path($confPath);
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{CONFIG_PATH}  = $confPath;

    my $yaml = YAML::Tiny->read('elasticsearch.yml');

    my $clusterName = $yaml->[0]->{'cluster.name'};
    my $nodeName    = $yaml->[0]->{'node.name'};
    my $port        = $yaml->[0]->{'http.port'};
    if ( not defined($port) ) {
        $port = 9200;
    }

    my $initNodes       = $yaml->[0]{'discovery.seed_hosts'};
    my $initMasterNodes = $yaml->[0]{'cluster.initial_master_nodes'};
    $appInfo->{CLUSTER_NAME}         = $clusterName;
    $appInfo->{NODE_NAME}            = $nodeName;
    $appInfo->{PORT}                 = $port;
    $appInfo->{CLUSTER_MEMBERS}      = $initNodes;
    $appInfo->{INITIAL_MASTER_NODES} = $initMasterNodes;

    my $javaHome;
    my $javaVersion;
    my $javaPath = readlink('/proc/$pid/exe');
    if ( not defined($javaPath) ) {
        if ( $cmdLine =~ /^(.*?\bjava)/ ) {
            $javaPath = $1;
            if ( $javaPath =~ /^\.{1,2}[\/\\]/ ) {
                $javaPath = "$workPath/$javaPath";
            }
        }

        if ( not -e $javaPath ) {
            $javaHome = $envMap->{JAVA_HOME};
            if ( defined($javaHome) ) {
                $javaPath = "$javaHome/bin/java";
            }
        }
        if ( -e $javaPath ) {
            $javaPath = Cwd::abs_path($javaPath);
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

    my $version;
    my $verInfo = $self->getCmdOut("$homePath/bin/elasticsearch -V | grep Version");
    if ( $verInfo =~ /^Version:\s*([\d\.]+)/ ) {
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

    $appInfo->{ADMIN_PORT}     = $port;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $jmxPort;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}
