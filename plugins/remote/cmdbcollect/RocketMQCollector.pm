#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package RocketMQCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use JSON;
use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use XML::MyXML qw(xml_to_object);
use Cwd 'realpath';
use CollectObjCat;

sub getConfig {
    return {
        regExps => ['\borg.apache.rocketmq\b'],    #正则表达是匹配ps输出
        psAttrs => { COMM => 'java' }
    };
}

sub loadBrokerConf() {
    my ( $self, $confFile ) = @_;

    #用来存放结果数组
    my $config = {};
    my $fh     = IO::File->new("<$confFile");

    while ( my $line = $fh->getline() ) {
        $line         =~ s/^\s*|\s*$//g;
        next if $line =~ /^#/;
        $line         =~ s/#.*$//;
        my @confItem = split( /\s*=\s*/, $line, 2 );
        if ( $#confItem == 1 ) {
            $config->{ $confItem[0] } = $confItem[1];
        }
    }

    return $config;
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo  = $self->{procInfo};
    my $mgmtIp    = $procInfo->{MGMT_IP};
    my $pid       = $procInfo->{PID};
    my $envMap    = $procInfo->{ENVIRONMENT};
    my $listenMap = $procInfo->{CONN_INFO}->{LISTEN};

    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $mainPid = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

# zcgl      341340  341317 /usr/local/java/jdk1.8.0_211/bin/java -server -Xms512m -Xmx512m -Xmn128m -XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=320m -XX:+UseConcMarkSweepGC -XX:+UseCMSCompactAtFullCollection -XX:CMSInitiatingOccupancyFraction=70 -XX:+CMSParallelRemarkEnabled -XX:SoftRefLRUPolicyMSPerMB=0 -XX:+CMSClassUnloadingEnabled -XX:SurvivorRatio=8 -XX:-UseParNewGC -verbose:gc -Xloggc:/dev/shm/rmq_srv_gc_%p_%t.log -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=5 -XX:GCLogFileSize=30m -XX:-OmitStackTraceInFastThrow -XX:-UseLargePages -cp .:/app/zcgl/rocketmq/bin/../conf:/app/zcgl/rocketmq/bin/../lib/*:.:/usr/local/java/jdk1.8.0_211/jre/lib/rt.jar:/usr/local/java/jdk1.8.0_211/lib/dt.jar:/usr/local/java/jdk1.8.0_211/lib/tools.jar org.apache.rocketmq.namesrv.NamesrvStartup
# zcgl      341389  341362 /usr/local/java/jdk1.8.0_211/bin/java -server -Xms4g -Xmx4g -XX:+UseG1GC -XX:G1HeapRegionSize=16m -XX:G1ReservePercent=25 -XX:InitiatingHeapOccupancyPercent=30 -XX:SoftRefLRUPolicyMSPerMB=0 -verbose:gc -Xloggc:/dev/shm/rmq_srv_gc_%p_%t.log -XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCApplicationStoppedTime -XX:+PrintAdaptiveSizePolicy -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=5 -XX:GCLogFileSize=30m -XX:-OmitStackTraceInFastThrow -XX:+AlwaysPreTouch -XX:MaxDirectMemorySize=15g -XX:-UseLargePages -XX:-UseBiasedLocking -cp .:/app/zcgl/rocketmq/bin/../conf:/app/zcgl/rocketmq/bin/../lib/*:.:/usr/local/java/jdk1.8.0_211/jre/lib/rt.jar:/usr/local/java/jdk1.8.0_211/lib/dt.jar:/usr/local/java/jdk1.8.0_211/lib/tools.jar org.apache.rocketmq.broker.BrokerStartup -c ../conf/2m-2s-sync/broker-a.properties
    my $mgmtIp = $procInfo->{MGMT_IP};
    my $osUser = $procInfo->{USER};

    $appInfo->{APP_IP} = $mgmtIp, $appInfo->{OS_USER} = $osUser;

    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    $self->getJavaAttrs($appInfo);
    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);
    $appInfo->{PORT} = $port;

    my $homePath  = readlink("/proc/$pid/cwd") . '../';
    my $classPath = $envMap->{CLASSPATH};
    if ( $cmdLine =~ /\s-cp\s*(.*?)\s+-/ ) {
        $classPath = $classPath . ':' . $1;
    }
    foreach my $clsDir ( split( ':', $classPath ) ) {
        if ( $clsDir eq '' ) {
            next;
        }
        if ( $clsDir =~ /^(.*?)\/lib\/\*/ or $clsDir =~ /^(.*?)\/lib\/rocketmq-namesrv-\d+jar/ ) {
            $homePath = $1;
            last;
        }
    }
    $homePath = realpath($homePath);

    my ( $confFile, $confPath );
    if ( $cmdLine =~ /\s-c\s+(.*?)\s+-/ or $cmdLine =~ /\s-c\s+(.*?)$/ ) {
        $confFile = $1;
        if ( $confFile =~ /^[\\\/]/ ) {
            $confFile = realpath($confFile);
        }
        else {
            $confFile = realpath("$homePath/bin/$confFile");
        }
        $confPath = dirname($confFile);
    }
    $appInfo->{INSTALL_PATH}     = $homePath;
    $appInfo->{CONFIG_PATH}      = $confPath;
    $appInfo->{CONFIG_FILE_PATH} = $confFile;

    if ( $cmdLine =~ /\borg.apache.rocketmq.namesrv.NamesrvStartup\b/ ) {
        $appInfo->{_APP_TYPE}    = 'rocketmq-namesrv';
        $appInfo->{UNIQUE_NAME}  = "rocketmq-namesrv-$mgmtIp-$port";
        $appInfo->{SERVER_NAME}  = "rocketmq-namesrv-$mgmtIp-$port";
        $appInfo->{SERVICE_NAME} = "rocketmq-namesrv";
    }
    elsif ( $cmdLine =~ /\borg.apache.rocketmq.broker.BrokerStartup\b/ ) {
        $appInfo->{_APP_TYPE} = 'rocketmq-broker';
        my $brokerConf = $self->loadBrokerConf($confFile);
        my $listenPort = $brokerConf->{'listenPort'};
        if ( $listenPort eq '' ) {
            $listenPort = $port;
        }
        $appInfo->{PORT}                     = $listenPort;
        $appInfo->{SERVICE_NAME}             = "rocketmq-broker";
        $appInfo->{UNIQUE_NAME}              = "rocketmq-broker-$mgmtIp-$listenPort";
        $appInfo->{SERVER_NAME}              = "rocketmq-broker-$mgmtIp-$listenPort";
        $appInfo->{BROKER_CLUSTER_NAME}      = $brokerConf->{'brokerClusterName'};         #集群名称
        $appInfo->{BROKER_NAME}              = $brokerConf->{'brokerName'};                #broker名称
        $appInfo->{BROKER_ID}                = $brokerConf->{'brokerId'};
        $appInfo->{NAMESRV_ADDR}             = $brokerConf->{'namesrvAddr'};               #nameServer地址列表
        $appInfo->{DEFAULT_TOPIC_QUEUE_NUMS} = $brokerConf->{'defaultTopicQueueNums'};     #默认主题队列数
        $appInfo->{AUTO_CREATE_TOPIC_ENABLE} = $brokerConf->{'autoCreateTopicEnable'};     #自动创建主题
        $appInfo->{DELETE_WHEN}              = $brokerConf->{'deleteWhen'};                #删除文件时间点
        $appInfo->{FILE_RESERVED_TIME}       = $brokerConf->{'fileReservedTime'};          #文件保留时间
        $appInfo->{MAPED_FILESIZE_COMMITLOG} = $brokerConf->{'mapedFileSizeCommitLog'};    #commit文件大小
        $appInfo->{DISK_MAXUSED_SPACE_RATIO} = $brokerConf->{'diskMaxUsedSpaceRatio'};     #检测物理文件磁盘空间
        $appInfo->{STORE_PATH_ROOT_DIR}      = $brokerConf->{'storePathRootDir'};          #存储路径
        $appInfo->{STORE_PATH_COMMITLOG}     = $brokerConf->{'storePathCommitLog'};        #commitLog存储路径
        $appInfo->{STORE_PATH_CONSUME_QUEUE} = $brokerConf->{'storePathConsumeQueue'};     #消费队列存储路径存储路径
        $appInfo->{STORE_PATH_INDEX}         = $brokerConf->{'storePathIndex'};            #消息索引存储路径
        $appInfo->{STORE_CHECKPOINT}         = $brokerConf->{'storeCheckpoint'};           #checkpoint文件存储路径
        $appInfo->{ABORT_FILE}               = $brokerConf->{'abortFile'};                 #abort文件存储路径
        $appInfo->{MAX_MESSAGE_SIZE}         = $brokerConf->{'maxMessageSize'};            #限制的消息大小
        $appInfo->{BROKER_ROLE}              = $brokerConf->{'brokerRole'};
    }

    my @collectSet = ($appInfo);

    my $rocketmqVersion = '';
    my $mqadminPath     = "$homePath/bin/mqadmin";
    my $outLines        = $self->getCmdOutLines( qq{$mqadminPath clusterList -n 127.0.0.1:$port 2>/dev/null}, $osUser );

    #/app/zcgl/rocketmq/bin/mqadmin clusterList -n 10.4.36.245:9876
    #Cluster Name     #Broker Name            #BID  #Addr                  #Version                #InTPS(LOAD)       #OutTPS(LOAD) #PCWait(ms) #Hour #SPACE
    #rocketmq-cluster  broker-a                0     10.4.39.232:10911      V4_9_4                   0.00(0,0ms)         0.00(0,0ms)          0 10960.96 0.6600
    #rocketmq-cluster  broker-a                1     10.4.36.245:10915      V4_9_4                   0.00(0,0ms)         0.00(0,0ms)          0 10960.96 0.8300
    if ( scalar(@$outLines) > 0 ) {
        my @memberIps       = ();
        my @memberPeer      = ();
        my $memberIpPortMap = {};
        foreach my $outLine (@$outLines) {
            if ( $outLine =~ /^#/ ) {
                next;
            }
            my @tmp        = split( /\s+/, $outLine );
            my $brokerAddr = $tmp[3];
            $rocketmqVersion = $tmp[4];
            my ( $brokerIp, $brokerPort ) = split( ":", $brokerAddr );
            $memberIpPortMap->{$brokerIp} = $brokerPort;
            push( @memberIps,  $brokerIp );
            push( @memberPeer, $brokerAddr );
        }

        if ( scalar(@memberIps) > 1 ) {
            my @sortedMemberIps = sort(@memberIps);
            my $primaryIp       = $sortedMemberIps[0];
            my $primaryPort     = $memberIpPortMap->{$primaryIp};
            my $uniqName        = "RocketMQ-$primaryIp:$primaryPort";
            my $clusterInfo = {
                _OBJ_CATEGORY     => CollectObjCat->get('CLUSTER'),
                _OBJ_TYPE         => 'RocketMQCluster',
                NAME              => $uniqName,
                UNIQUE_NAME       => $uniqName,
                PRIMARY_IP        => $primaryIp,
                PORT              => $primaryPort,
                CLUSTER_MODE      => 'distribute',
                CLUSTER_SOFTWARE  => 'RocketMQ',
                CLUSTER_VERSION   => $rocketmqVersion,
                MEMBER_PEER       => \@memberPeer,
                NOT_PROCESS       => 1
            };

            push( @collectSet, $clusterInfo );
        }
    }

    if( $rocketmqVersion == '') {
        my ($status, $outLines) = $self->getCmdOutLines(qq{unzip -p "$homePath/lib/rocketmq-client-*.jar" META-INF/MANIFEST.MF});
        if ( $status == 0){
            foreach my $line (@$outLines){
                if ($line =~ /Implementation-Version\s*:\s*(.*)\s*$/){
                    $rocketmqVersion = $1;
                }
            }
        }
    }

    $appInfo->{VERSION} = $rocketmqVersion;

    return @collectSet;
}

1;
