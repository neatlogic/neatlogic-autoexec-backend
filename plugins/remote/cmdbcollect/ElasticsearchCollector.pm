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
use CollectObjCat;

sub getConfig {
    return {
        regExps  => ['\borg.elasticsearch.bootstrap.Elasticsearch\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                                   #ps的属性的精确匹配
        envAttrs => {}                                                    #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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
    my $envMap           = $procInfo->{ENVIRONMENT};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $user     = $procInfo->{USER};
    my $workPath = readlink("/proc/$pid/cwd");

    #-Des.path.home=/opt/elasticsearch-7.5.1 -Des.path.conf=/opt/elasticsearch-7.5.1/config -Des.distribution.flavor=oss
    my $homePath;
    my $confPath;

    if ( $cmdLine =~ /\s-Des.path.home=(.*?)\s+-/ ) {
        $homePath = $1;
        $homePath =~ s/^["']|["']$//g;
        if ( $homePath =~ /^\.{1,2}[\/\\]/ ) {
            $homePath = "$workPath/$homePath";
        }
        $homePath = Cwd::abs_path($homePath);
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine not a elasticsearch process.\n");
        return;
    }

    $self->getJavaAttrs($appInfo);

    my $version;
    my $verInfo = $self->getCmdOut("$homePath/bin/elasticsearch -V | grep Version");
    if ( $verInfo =~ /^Version:\s*([\d\.]+)/ ) {
        $version = $1;
    }
    $appInfo->{VERSION} = $version;

    if ( $version =~ /(\d+)/ ) {
        $appInfo->{MAJOR_VERSION} = "ElasticSearch$1";
    }

    if ( $cmdLine =~ /\s-Des.path.conf=(.*?)\s+-/ ) {
        $confPath = $1;
        $confPath =~ s/^["']|["']$//g;
        if ( $confPath =~ /^\.{1,2}[\/\\]/ ) {
            $confPath = "$workPath/$confPath";
        }
        $confPath = Cwd::abs_path($confPath);
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{CONFIG_PATH}  = $confPath;

    my $servicePorts = $appInfo->{SERVICE_PORTS};
    if ( not defined($servicePorts) ) {
        $servicePorts = {};
        $appInfo->{SERVICE_PORTS} = $servicePorts;
    }

    my $yaml = YAML::Tiny->read('elasticsearch.yml');

    my $clusterName = $yaml->[0]->{'cluster.name'};
    my $nodeName    = $yaml->[0]->{'node.name'};
    my $port        = $yaml->[0]->{'http.port'};
    my $sslPort     = $yaml->[0]->{'https.port'};
    if ( defined($port) ) {
        $servicePorts->{http} = $port;
    }
    else {
        $port = $sslPort;
    }

    if ( defined($sslPort) ) {
        $servicePorts->{https} = $sslPort;
    }

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

    $appInfo->{ADMIN_PORT}     = $port;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}

1;
