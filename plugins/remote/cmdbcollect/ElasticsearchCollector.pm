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
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');
    $appInfo->{_OBJ_TYPE}     = 'Elasticsearch';

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
    $appInfo->{MGMT_IP}     = $procInfo->{MGMT_IP};

    my $servicePorts = $appInfo->{SERVICE_PORTS};
    if ( not defined($servicePorts) ) {
        $servicePorts = {};
        $appInfo->{SERVICE_PORTS} = $servicePorts;
    }

    my $yaml = YAML::Tiny->read("$confPath/elasticsearch.yml");

    my $clusterName = $yaml->[0]->{'cluster.name'};
    my $nodeName    = $yaml->[0]->{'node.name'};
    my $port        = $yaml->[0]->{'http.port'};
    $port           = int($port);
    my $sslPort     = $yaml->[0]->{'https.port'};
    $sslPort        = int($sslPort);
    my $timeout     = $yaml->[0]->{'discovery.zen.fd.ping_timeout'};
    my $auth        = $yaml->[0]->{'xpack.security.enabled'};
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
    my $masterName;
    if ($initMasterNodes =~ /\["([^"]+)"\]/){
        $masterName = $1;
    }

    my $nodes = $yaml->[0]{'discovery.zen.ping.unicast.hosts'};
    my @n;
    # 使用正则表达式提取 IP:Port
    while ($nodes =~ /(\d+\.\d+\.\d+\.\d+)/g) {
        push (@n, $1);
    }
    my $nodesCount = scalar @n;
    my $node_str = join(',',@n);
    $appInfo->{CLUSTER_NAME}         = $clusterName;
    $appInfo->{INSTANCE_NAME}        = $nodeName;
    $appInfo->{NODE_NAME}            = $nodeName;
    $appInfo->{PORT}                 = $port;
    $appInfo->{CLUSTER_MEMBERS}      = $initNodes;
    $appInfo->{INITIAL_MASTER_NODES} = $masterName;
    $appInfo->{NODES_COUNT}          = $nodesCount;
    $appInfo->{NODES}                = $node_str;

    my @dbConns = ();
    my @all_ins;
    foreach my $item (@n){
        my $ins;
        $ins->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');
        $ins->{_OBJ_TYPE}     = 'Elasticsearch';
        $ins->{INSTANCE_NAME} = $appInfo->{CLUSTER_NAME};
        $ins->{MGMT_IP}       = $item;
        $ins->{PORT}          = $port;
        push (@all_ins, $ins);

        my $conn;
        $conn->{_OBJ_CATEGORY} = CollectObjCat->get('DB');
        $conn->{_OBJ_TYPE} = 'DB-CONNECT';
        $conn->{IP} = $item;
        $conn->{PORT} = $port;
        $conn->{USER} = '-';
        $conn->{SERVICE_NAME} = $appInfo->{CLUSTER_NAME};
        push (@dbConns,$conn);
    }

    my @dbNames = ();
    push(
            @dbNames,
            {
                _OBJ_CATEGORY => CollectObjCat->get('DB'),
                _OBJ_TYPE     => 'Elasticsearch-DB',
                NAME          => $appInfo->{CLUSTER_NAME},
                VERSION       => $appInfo->{VERSION},
                AUTHENTICATION       => $auth,
                PRIMARY_NODE       => $appInfo->{INITIAL_MASTER_NODES},
                NODES_COUNT       => $appInfo->{NODES_COUNT},
                NODES       => $appInfo->{NODES},
                TIMEOUT     => $timeout,
                PRIMARY_IP    => $appInfo->{MGMT_IP},
                #VIP           => $vip,
                PORT          => $port,
                CONNECTIONS   => \@dbConns,
                #SERVICE_ADDR  => "$vip:$port",
                INSTANCES     => \@all_ins
            }
        );
    if ($masterName eq $nodeName){
        $appInfo->{ROLE}             = 'master';
        $appInfo->{DATABASES}        = \@dbNames;
    }else{
        $appInfo->{ROLE}             = 'data';
    }

    $appInfo->{ADMIN_PORT}     = $port;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}

1;
