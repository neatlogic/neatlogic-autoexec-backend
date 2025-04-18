#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package KafkaCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use JSON;
use Socket;

sub getConfig {
    return {
        regExps  => ['\bkafka.Kafka\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },     #ps的属性的精确匹配
        envAttrs => {}                      #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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
    my $exeFile          = $procInfo->{EXECUTABLE_FILE};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};
    my $osUser  = $procInfo->{USER};

    my $homePath;
    my $version;

    my $kafkaLibPath;
    if ( $cmdLine =~ /-cp\s+.*[:;]([\/\\].*[\/\\]kafka.*?.jar)/ ) {
        $kafkaLibPath = Cwd::abs_path( dirname($1) );
    }
    elsif ( $envMap->{CLASSPATH} =~ /.*[:;]([\/\\].*[\/\\]kafka.*?.jar)/ ) {
        $kafkaLibPath = Cwd::abs_path( dirname($1) );
    }

    if ( defined($kafkaLibPath) ) {
        $homePath = dirname($kafkaLibPath);
        foreach my $lib ( glob("$kafkaLibPath/kafka_*.jar") ) {
            if ( $lib =~ /kafka_([\d\.]+).*?\.jar/ ) {
                $version = $1;
                $appInfo->{MAIN_LIB} = $lib;
            }
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: Can not find homepath for Kafka command:$cmdLine, failed.\n");
        return;
    }

    $appInfo->{INSTALL_PATH} = $homePath;
    $appInfo->{BIN_PATH}     = dirname($exeFile);
    $appInfo->{EXE_PATH}     = $exeFile;
    $appInfo->{VERSION}      = $version;
    if ( $version =~ /(\d+)/ ) {
        $appInfo->{MAJOR_VERSION} = "kafka$1";
    }

    my $pos      = rindex( $cmdLine, 'kafka.Kafka' ) + 12;
    my $confPath = substr( $cmdLine, $pos );
    $confPath =~ s/^\s*|\s*$//g;

    my $realConfPath = $confPath;
    if ( $confPath =~ /^\.{1,2}[\/\\]/ ) {
        if ( -e "/proc/$pid/cwd" ) {
            my $workPath = readlink("/proc/$pid/cwd");
            $realConfPath = Cwd::abs_path("$workPath/$confPath");
        }
        if ( not -e $realConfPath ) {
            $realConfPath = Cwd::abs_path("$homePath/$confPath");
        }
        if ( not -e $realConfPath ) {
            $realConfPath = Cwd::abs_path("$homePath/bin/$confPath");
        }
    }
    else {
        $realConfPath = Cwd::abs_path($confPath);
    }

    if ( defined($realConfPath) ) {
        $confPath                    = $realConfPath;
        $appInfo->{CONFIG_PATH}      = dirname($realConfPath);
        $appInfo->{CONFIG_FILE_PATH} = $realConfPath;
    }
    $self->getJavaAttrs($appInfo);
    my $servicePorts = $appInfo->{SERVICE_PORTS};
    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);

    my @members;
    my $confMap   = {};
    my $confLines = $self->getFileLines($confPath);
    foreach my $line (@$confLines) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line !~ /^#/ ) {
            my ( $key, $val ) = split( /\s*=\s*/, $line );
            $confMap->{$key} = $val;
        }
    }

#auto.create.topics.enable==>false
#auto.leader.rebalance.enable==>true
#compression.type==>producer
#controlled.shutdown.enable==>true
#controlled.shutdown.max.retries==>3
#controlled.shutdown.retry.backoff.ms==>5000
#controller.message.queue.size==>10
#controller.socket.timeout.ms==>30000
#default.replication.factor==>1
#delete.topic.enable==>true
#external.kafka.metrics.exclude.prefix==>kafka.network.RequestMetrics,kafka.server.DelayedOperationPurgatory,kafka.server.BrokerTopicMetrics.BytesRejectedPerSec
#external.kafka.metrics.include.prefix==>kafka.network.RequestMetrics.ResponseQueueTimeMs.request.OffsetCommit.98percentile,kafka.network.RequestMetrics.ResponseQueueTimeMs.request.Offsets.95percentile,kafka.network.RequestMetrics.ResponseSendTimeMs.request.Fetch.95percentile,kafka.network.RequestMetrics.RequestsPerSec.request
#fetch.purgatory.purge.interval.requests==>10000
#inter.broker.protocol.version==>2.0-IV1
#kafka.ganglia.metrics.group==>kafka
#kafka.ganglia.metrics.host==>localhost
#kafka.ganglia.metrics.port==>8671
#kafka.ganglia.metrics.reporter.enabled==>true
#kafka.metrics.reporters==>
#kafka.timeline.metrics.host_in_memory_aggregation==>
#kafka.timeline.metrics.host_in_memory_aggregation_port==>
#kafka.timeline.metrics.host_in_memory_aggregation_protocol==>
#kafka.timeline.metrics.hosts==>
#kafka.timeline.metrics.maxRowCacheSize==>10000
#kafka.timeline.metrics.port==>
#kafka.timeline.metrics.protocol==>
#kafka.timeline.metrics.reporter.enabled==>true
#kafka.timeline.metrics.reporter.sendInterval==>5900
#kafka.timeline.metrics.truststore.password==>
#kafka.timeline.metrics.truststore.path==>
#kafka.timeline.metrics.truststore.type==>
#kerberos.auth.enable==>false
#leader.imbalance.check.interval.seconds==>300
#leader.imbalance.per.broker.percentage==>10
#listeners==>PLAINTEXT://hybrid01.classic-pr-hangzhou-01.tailongpre.deploy.sensorsdata.cloud:9092
#log.cleaner.dedupe.buffer.size==>134217728
#log.cleaner.delete.retention.ms==>604800000
#log.cleaner.enable==>true
#log.cleaner.min.cleanable.ratio==>0.5
#log.cleaner.threads==>1
#log.cleanup.interval.mins==>10
#log.dirs==>/sensorsdata/seqdata00/kafka/data
#log.index.interval.bytes==>4096
#log.index.size.max.bytes==>10485760
#log.message.format.version==>2.0-IV1
#log.retention.bytes==>-1
#log.retention.check.interval.ms==>300000
#log.retention.hours==>168
#log.roll.hours==>168
#log.segment.bytes==>1073741824
#max.connections.per.ip==>1000
#message.max.bytes==>10485760
#min.insync.replicas==>2
#num.io.threads==>8
#num.network.threads==>3
#num.partitions==>1
#num.recovery.threads.per.data.dir==>1
#num.replica.fetchers==>1
#offset.metadata.max.bytes==>4096
#offsets.commit.required.acks==>-1
#offsets.commit.timeout.ms==>5000
#offsets.load.buffer.size==>5242880
#offsets.retention.check.interval.ms==>600000
#offsets.retention.minutes==>525600
#offsets.topic.compression.codec==>0
#offsets.topic.num.partitions==>50
#offsets.topic.replication.factor==>2
#offsets.topic.segment.bytes==>104857600
#port==>9092
#producer.metrics.enable==>false
#producer.purgatory.purge.interval.requests==>10000
#queued.max.requests==>500
#replica.fetch.max.bytes==>11534336
#replica.fetch.min.bytes==>1
#replica.fetch.wait.max.ms==>500
#replica.high.watermark.checkpoint.interval.ms==>5000
#replica.lag.max.messages==>4000
#replica.lag.time.max.ms==>30000
#replica.socket.receive.buffer.bytes==>65536
#replica.socket.timeout.ms==>30000
#sasl.enabled.mechanisms==>GSSAPI
#sasl.mechanism.inter.broker.protocol==>GSSAPI
#security.inter.broker.protocol==>PLAINTEXT
#socket.receive.buffer.bytes==>102400
#socket.request.max.bytes==>104857600
#socket.send.buffer.bytes==>102400
#ssl.client.auth==>none
#ssl.key.password==>
#ssl.keystore.location==>
#ssl.keystore.password==>
#ssl.truststore.location==>
#ssl.truststore.password==>
#unclean.leader.election.enable==>false
#zookeeper.connect==>hybrid01.classic-pr-hangzhou-01.tailongpre.deploy.sensorsdata.cloud:2181,hybrid02.classic-pr-hangzhou-01.tailongpre.deploy.sensorsdata.cloud:2181,hybrid03.classic-pr-hangzhou-01.tailongpre.deploy.sensorsdata.cloud:2181
#zookeeper.connection.timeout.ms==>25000
#zookeeper.session.timeout.ms==>30000
#zookeeper.sync.time.ms==>2000
    $appInfo->{BROKER_ID} = $confMap->{'broker.id'};
    my $lsnAddr = $confMap->{'advertised.listeners'};
    $appInfo->{ACCESS_ADDR} = $lsnAddr;
    if ( $lsnAddr =~ /:(\d+)$/ ) {
        $port = int($1);
    }

    if ( $port == 65535 ) {
        print("WARN: Can not determine Kafaka listen port.\n");
        return undef;
    }

    $appInfo->{PORT}     = $port;
    $servicePorts->{tcp} = $port;

    my @logDirs = ();
    foreach my $logDir ( split( ',', $confMap->{'log.dirs'} ) ) {
        push( @logDirs, { VALUE => $logDir } );
    }
    $appInfo->{LOG_DIRS} = \@logDirs;
    my $zookeeper_connect = $confMap->{'zookeeper.connect'};
    my @zookeeperConnects = ();
    foreach my $zookeeperConn ( split( ',', $zookeeper_connect ) ) {
        push( @zookeeperConnects, { VALUE => $zookeeperConn } );
    }
    $appInfo->{ZOOKEEPER_CONNECTS} = \@zookeeperConnects;

    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    my @collectSet = ($appInfo);

    my $zookeeper_shell     = "$homePath/bin/zookeeper-shell.sh";                                                                     # zookeeper-shell.sh的路径
    my $kafka_path          = "/brokers/ids";                                                                                         # Kafka broker IDs在ZooKeeper中的路径，这个可能需要根据你的配置进行调整
    my $broker_ids_outLines = $self->getCmdOutLines( qq{$zookeeper_shell $zookeeper_connect ls $kafka_path 2>/dev/null}, $osUser );

    my @broker_ids;
    if ( scalar(@$broker_ids_outLines) > 0 ) {
        foreach my $outLine (@$broker_ids_outLines) {
            if ( $outLine =~ /^\[.*\]$/ ) {
                $outLine =~ s/\[|\]//g;
                @broker_ids = split( ',', $outLine );

                # 对每个分割得到的元素应用trim函数
                @broker_ids = map { trim($_) } @broker_ids;
            }
        }
    }

    if ( scalar(@broker_ids) > 1 ) {
        my @memberPeers = ();

        # 对于每个broker ID，查询详细的broker信息
        foreach my $broker_id (@broker_ids) {
            my $broker_info_command  = "$zookeeper_shell $zookeeper_connect get $kafka_path/$broker_id 2>/dev/null";
            my $broker_info_outLines = $self->getCmdOutLines( qq{$broker_info_command}, $osUser );
            if ( scalar(@$broker_info_outLines) > 0 ) {
                foreach my $outLine (@$broker_info_outLines) {

                    #{"features":{},"listener_security_protocol_map":{"PLAINTEXT":"PLAINTEXT"},"endpoints":["PLAINTEXT://data-sta-zjjyy001:9092"],"jmx_port":-1,"port":9092,"host":"data-sta-zjjyy001","version":5,"timestamp":"1720499608615"}
                    my $brokerHost;
                    my $brokerPort;
                    if ( $outLine =~ /"host":/ and $outLine =~ /"port":/ and $outLine =~ /"listener_security_protocol_map":/ ) {
                        my $brokerJson = {};
                        $brokerJson = from_json($outLine);
                        $brokerHost = $brokerJson->{host};
                        $brokerPort = $brokerJson->{port};
                    }

                    if ( defined($brokerHost) and $brokerHost ne "" and defined($brokerPort) and $brokerPort ne "" ) {
                        my $brokerIp = gethostbyname($brokerHost);
                        if ( defined($brokerIp) ) {
                            $brokerIp = inet_ntoa($brokerIp);
                        }
                        push( @memberPeers, "$brokerIp:$brokerPort" );
                    }
                }
            }
        }

        my @sortedMemberPeers = sort(@memberPeers);
        my $primaryAddr       = $sortedMemberPeers[0];
        my ( $primaryIp, $primaryPort ) = split( ':', $primaryAddr, 2 );

        my $uniqName    = "Kafka:$primaryIp:$primaryPort";
        my $clusterInfo = {
            _OBJ_CATEGORY    => CollectObjCat->get('CLUSTER'),
            _OBJ_TYPE        => 'KafkaCluster',
            NAME             => $uniqName,
            UNIQUE_NAME      => $uniqName,
            PRIMARY_IP       => $primaryIp,
            PORT             => $primaryPort,
            CLUSTER_SOFTWARE => 'Kafka',
            CLUSTER_MODE     => 'Zookeeper',
            CLUSTER_VERSION  => $version,
            MEMBER_PEER      => \@sortedMemberPeers,
            NOT_PROCESS      => 1
        };
        push( @collectSet, $clusterInfo );
    }

    return @collectSet;
}

# 定义一个trim函数，用于去除字符串前后的空白字符
sub trim {
    my ($s) = @_;
    $s =~ s/^\s+|\s+$//g;
    return $s;
}

1;
