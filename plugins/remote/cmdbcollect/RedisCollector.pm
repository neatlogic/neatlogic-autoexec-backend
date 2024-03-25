#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package RedisCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Socket;
use JSON;
use File::Spec;
use File::Basename;
use IO::File;
use File::Copy;
use Cwd qw(realpath);
use CollectObjCat;
use RedisExec;

sub getConfig {
    return {
        regExps => ['\bredis-server\s'],         #正则表达是匹配ps输出
        psAttrs => { COMM => 'redis-server' }    #ps的属性的精确匹配
    };
}

#配置文件
sub parseConfig {
    my ( $self, $configFile, $redisInfo ) = @_;
    my $configData = $self->getFileLines($configFile);

    #只取定义的配置
    my $filter = {
        "dbfilename"     => 1,
        "dir"            => 1,
        "logfile"        => 1,
        "loglevel"       => 1,
        "port"           => 1,
        "requirepass"    => 1,
        "masterauth"     => 1,
        "appendonly"     => 1,
        "appendfilename" => 1
    };
    foreach my $line (@$configData) {
        $line =~ s/^\s*|\s*$//g;

        if ( $line =~ /^#/ or $line eq '' ) {
            next;
        }

        my @values = split( /\s+/, $line, 2 );
        if ( scalar(@values) > 1 ) {
            my $key = $values[0];
            $key =~ s/^\s*|\s*$//g;
            my $value = $values[1];
            $value =~ s/^\s*['"]|['"]\s*$//g;
            if ( defined( $filter->{$key} ) ) {
                $redisInfo->{ uc($key) } = $value;
            }
        }
    }
}

#从可能得配置文件中找到对应redis的auth
sub getPassFromConf() {
    my ( $self, $pid, $user, $workingDir, $mgmtIp, $port ) = @_;

    my $procInfo        = $self->{procInfo};
    my $exePath         = $procInfo->{EXECUTABLE_FILE};
    my $redisInstallDir = dirname($exePath);
    my $userHomeDir     = ( getpwnam($user) )[7];

    my @possiblePasswords = ();
    my $redisConfFiles    = $self->getCmdOutLines(qq{find $redisInstallDir $workingDir $userHomeDir -name "*.conf"});
    unshift( @$redisConfFiles, "" );
    foreach my $confFile (@$redisConfFiles) {
        $confFile =~ s/^\s*|\s*$//g;
        if ( not -f $confFile ) {
            next;
        }
        my $confLines = $self->getFileLines($confFile);
        foreach my $confLine (@$confLines) {
            if ( $confLine =~ /^\s*requirepass\s+(.*?)\s*$/ ) {
                push( @possiblePasswords, $1 );
            }
        }
    }

    my $password = undef;
    foreach my $possiblePass (@possiblePasswords) {

        #尝试执行redis-cli，看是否正常进入
        my $result = $self->getCmdOut(qq{$redisInstallDir/redis-cli -a $possiblePass -h $mgmtIp -p $port info 2>/dev/null});
        if ( $result !~ "NOAUTH Authentication required." ) {
            $password = $possiblePass;
        }
    }

    return $password;
}

sub getRedisInfo {
    my ( $self, $redisCliCmd ) = @_;

    # # CPU
    # used_cpu_sys:8010.007240
    # used_cpu_user:9695.356001
    # used_cpu_sys_children:0.000000
    # used_cpu_user_children:0.000000
    # # Sentinel
    # sentinel_masters:1
    # sentinel_tilt:0
    # sentinel_running_scripts:0
    # sentinel_scripts_queue_length:0
    # sentinel_simulate_failure_flags:0
    # master0:name=mymaster,status=ok,address=10.4.96.42:6379,slaves=2,sentinels=3

    my $infoByCliByCli = {};
    my $outLines       = $self->getCmdOutLines(qq{$redisCliCmd info 2>/dev/null});
    foreach my $outLine (@$outLines) {
        if ( $outLine =~ /^#/ ) {
            next;
        }
        my ( $key, $val ) = split( /:/, $outLine, 2 );
        $val =~ s/^\s*|\s*$//g;
        $infoByCliByCli->{$key} = $val;
    }

    return $infoByCliByCli;
}

sub getMaxClientsCount {
    my ( $self, $redisCliCmd ) = @_;

    # 1) "maxclients"
    # 2) "10000"
    my $maxClients;
    my $maxClientsLines = $self->getCmdOutLines(qq{$redisCliCmd config get maxclients 2>/dev/null});
    foreach my $maxClientsLine (@$maxClientsLines) {
        if ( $maxClientsLine =~ /"(\d+)"/ ) {
            $maxClients = int($1);
        }
    }
    return $maxClients;
}

sub getSentinels {
    my ( $self, $redisCliCmd ) = @_;

    my @sentinels = ();

    # id=12 addr=10.4.96.40:48150 fd=10 name=sentinel-d7954ff8-cmd age=9477547 idle=0 flags=N db=0 sub=0 psub=0 multi=-1 qbuf=0 qbuf-free=0 obl=0 oll=0 omem=0 events=r cmd=publish
    # id=422 addr=10.4.96.42:44772 fd=9 name=sentinel-a72a436c-pubsub age=23172 idle=0 flags=P db=0 sub=1 psub=0 multi=-1 qbuf=0 qbuf-free=0 obl=0 oll=0 omem=0 events=r cmd=subscribe
    # id=423 addr=10.4.96.40:39578 fd=12 name=sentinel-d7954ff8-pubsub age=23172 idle=0 flags=P db=0 sub=1 psub=0 multi=-1 qbuf=0 qbuf-free=0 obl=0 oll=0 omem=0 events=r cmd=subscribe
    my $outLines = $self->getCmdOutLines(qq{$redisCliCmd client list 2>/dev/null});
    foreach my $outLine (@$outLines) {
        if ( $outLine =~ /sentinel-.*?-pubsub/ ) {
            for my $attrLine ( split( /\s+/, $outLine, 3 ) ) {
                if ( $attrLine =~ /(\w+)=(.*?)/ ) {
                    my $key = $1;
                    my $val = $2;
                    push( @sentinels, { $key => $val } );
                }
            }
        }
    }

    return \@sentinels;
}

sub getSentinelMasters {
    my ( $self, $redisCliCmd ) = @_;

    # # Sentinel
    # sentinel_masters:1
    # sentinel_tilt:0
    # sentinel_running_scripts:0
    # sentinel_scripts_queue_length:0
    # sentinel_simulate_failure_flags:0
    # master0:name=mymaster,status=ok,address=10.4.96.42:6379,slaves=2,sentinels=3

    my @masters;
    my $outLines = $self->getCmdOutLines(qq{$redisCliCmd client info Sentinel 2>/dev/null});
    foreach my $outLine (@$outLines) {
        if ( $outLine =~ /^master\d+:(.*?)$/ ) {
            my $val = $1;
            foreach my $masterAttr ( split( /,/, $val ) ) {
                my $masterInfo = {};
                if ( $masterAttr =~ /(\w+)=(.*)$/ ) {
                    $masterInfo->{$1} = $2;
                }
                push( @masters, $masterInfo );
            }
        }
    }

    return \@masters;
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
sub collect {
    my ($self) = @_;

    $self->{isVerbose} = 1;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $pid       = $procInfo->{PID};
    my $osUser    = $procInfo->{USER};
    my $mgmtIp    = $procInfo->{MGMT_IP};
    my $redisInfo = {};
    $redisInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');

    #设置此采集到的对象对象类型，可以是：CollectObjCat->get('INS')，CollectObjCat->get('DBINS')，CollectObjCat::OS
    my $command  = $procInfo->{COMMAND};
    my $comm     = $procInfo->{COMM};
    my $exePath  = $procInfo->{EXECUTABLE_FILE};
    my $binPath  = dirname($exePath);
    my $homePath = dirname($binPath);
    $redisInfo->{INSTALL_PATH} = $homePath;

    #Redis server v=3.2.12 sha=00000000:0 malloc=jemalloc-3.6.0 bits=64 build=7897e7d0e13773f
    my $verInfo = $self->getCmdOut(qq{"$exePath" -v});
    if ( $verInfo =~ /v=([\d\.]+)/ ) {
        my $version = $1;
        $redisInfo->{VERSION} = $version;
        if ( $version =~ /(\d+)/ ) {
            $redisInfo->{MAJOR_VERSION} = "Redis$1";
        }
    }

    my $configFile = File::Spec->catfile( $binPath, "redis.conf" );
    if ( not -e $configFile ) {
        $configFile = File::Spec->catfile( $homePath, "redis.conf" );
        if ( not -e $configFile ) {
            $configFile = undef;
            if ( $command =~ /redis-server\s+(\S+)/ ) {
                my $possibleCfgFile = $1;
                if ( -e $possibleCfgFile ) {
                    $configFile = $possibleCfgFile;
                }
            }

            if ( not defined($configFile) and -e '/etc/redis.conf' ) {
                $configFile = '/etc/redis.conf';
            }
        }
    }
    $configFile = realpath($configFile);
    my $cliFile = File::Spec->catfile( $binPath, "redis-cli" );
    $redisInfo->{CONFIG_FILE} = $configFile;

    #检查是否装了reds-cli
    if ( not -e $cliFile and -e "$FindBin::Bin/redis-cli" ) {

        #需要改为自动到介质中心下载
        copy( "$FindBin::Bin/redis-cli", $binPath );
        chmod( 0755, "$binPath/redis-cli" );
    }

    my ( $ports, $port ) = $self->getPortFromProcInfo($redisInfo);

    #如果redis存在哨兵进程，则通过哨兵端口进行连接
    my $cliPort;
    my $sentinelLsnLines = $self->getCmdOutLines(qq{netstat -nlp |grep $port|grep redis-senti});
    foreach my $lsnLines (@$sentinelLsnLines) {
        my $lsnAddr = ( split( /\s+/, $lsnLines ) )[3];
        if ( $lsnAddr =~ /:(\d+)$/ ) {
            $cliPort = int($1);
            print("INFO: Connect info by redis sentinel, port:$cliPort.\n");
            last;
        }
    }
    if ( not defined($cliPort) ) {
        $cliPort = $port;
    }
    my $workingDir = readlink("/proc/$pid/cwd");
    my $auth       = $self->{defaultPassword};
    if ( not defined($auth) ) {
        $auth = $self->getPassFromConf( $pid, $osUser, $workingDir, '127.0.0.1', $port );
    }

    my $redisCliCmd = "$binPath/redis-cli -a $auth -h 127.0.0.1 -p $port";
    my $infoByCli   = $self->getRedisInfo($redisCliCmd);

    my $configFile = $infoByCli->{config_file};
    $configFile = realpath($configFile);
    $redisInfo->{CONFIG_FILE} = $configFile;

    #配置文件
    $self->parseConfig( $configFile, $redisInfo );

    if ( defined( $redisInfo->{TCP_PORT} ) ) {
        $port = int( $redisInfo->{TCP_PORT} );
    }

    if ( $command =~ /:(\d+)$/ or $command =~ /--port\s+(\d+)/ ) {
        $port = int($1);
    }

    if ( $port == 65535 ) {
        print("WARN: Can not determine the redis server listen port.\n");
        return undef;
    }

    $redisInfo->{PORT}           = $port;
    $redisInfo->{SSL_PORT}       = $port;
    $redisInfo->{ADMIN_PORT}     = $port;
    $redisInfo->{ADMIN_SSL_PORT} = $port;

    $redisInfo->{EXECUTABLE}         = $infoByCli->{executable};
    $redisInfo->{MULTIPLEXING_API}   = $infoByCli->{multiplexing_api};
    $redisInfo->{RUN_ID}             = $infoByCli->{run_id};
    $redisInfo->{CONFIG_MEMORY_SIZE} = $infoByCli->{maxmemory_human};
    my $AOF_ENABLED = $infoByCli->{aof_enabled};
    my $aofEnabled;
    if ($AOF_ENABLED) {
        $aofEnabled = 1;
    }
    else {
        $aofEnabled = 0;
    }
    $redisInfo->{AOF_ENABLED} = $aofEnabled;

    my $redisMode   = $infoByCli->{redis_mode};
    my $role        = $infoByCli->{role};
    my $masterHost  = $infoByCli->{master_host};
    my $masterPort  = $infoByCli->{master_port};
    my $masterAddr  = "$masterHost:$masterPort";
    my @memberPeers = ();

    $redisInfo->{REDIS_ROLE}       = $role;
    $redisInfo->{CLUSTER_MODE}     = undef;
    $redisInfo->{CLUSTER_ROLE}     = undef;
    $redisInfo->{IS_CLUSTER}       = 0;
    $redisInfo->{SENTINEL_MONITOR} = undef;

    my $sentinelsCount = 0;
    if ( $redisMode eq 'cluster' ) {
        $redisInfo->{CLUSTER_MODE} = 'master-slave';
        $redisInfo->{CLUSTER_ROLE} = $role;
        $redisInfo->{IS_CLUSTER}   = 1;
        if ( $role eq 'slave' ) {
            $redisInfo->{MASTER_IPS} = $masterHost . ":" . $masterPort;
        }
        else {
            my $slavesCount = int( $infoByCli->{connected_slaves} );
            my @slaveNodes  = ();
            for ( my $i = 0 ; $i < $slavesCount ; $i++ ) {
                my $slaveDesc = $infoByCli->{"slave$i"};
                if ( not defined($slaveDesc) or $slaveDesc eq '' ) {
                    next;
                }

                my ( $slaveHost, $slavePort );
                foreach my $slaveAddr ( split( /\s*,\s*/, $slaveDesc ) ) {
                    if ( $slaveAddr =~ /ip\s*=\s*(.*)\s*$/i ) {
                        $slaveHost = $1;
                    }
                    if ( $slaveAddr =~ /port\s*=\s*(.*)\s*$/i ) {
                        $slavePort = $1;
                    }
                }
                push( @memberPeers, "$slaveHost:$slavePort" );
                push( @slaveNodes,  { VALUE => $slaveHost . ":" . $slavePort } );
            }
            $redisInfo->{SLAVE_NODES} = \@slaveNodes;
            push( @memberPeers, $masterAddr );
        }
    }
    elsif ( $redisMode eq 'sentinel' ) {
        my $sentinelMasters = $self->getSentinelMasters($redisCliCmd);

        #TODO: SENTINELS原来只取一个，只是用来看，现在换成了文本化的json了
        $redisInfo->{SENTINEL_MONITOR} = to_json( $sentinelMasters, { pretty => 1 } );

        my $sentinels = $self->getSentinels($redisCliCmd);
        $sentinelsCount = scalar(@$sentinels);

        #TODO: SENTINELS原来是用逗号相隔，只是用来看，现在换成了文本化的json了
        $redisInfo->{SENTINELS} = to_json( $sentinels, { pretty => 1 } );

        foreach my $sentinelInfo (@$sentinels) {
            push( @memberPeers, $sentinelInfo->{addr} );
        }
    }

    $redisInfo->{MAX_CONNECTION} = $self->getMaxClientsCount($redisCliCmd);

    #对结果进行格式化转换
    if ( ( $redisMode eq "sentinel" ) || ( $redisMode eq "standalone" && $sentinelsCount > 0 ) ) {
        $redisMode = "master-slave";
    }
    elsif ( $redisMode eq "cluster" ) {
        $redisMode = "cluster";
    }
    else {
        $redisMode = "standalone";
    }

    my $redisDir = $redisInfo->{DIR};
    if ( not defined($redisDir) or $redisDir eq '' ) {
        $redisDir = $workingDir;
    }

    my $dbFilename = $redisInfo->{DBFILENAME};
    my $dbFilePath = $dbFilename;
    if ( $dbFilename !~ /[\/\\]/ ) {
        $dbFilePath = "$redisDir/$dbFilename";
    }
    $dbFilePath = realpath($dbFilePath);

    $redisInfo->{REDIS_MODE} = $redisMode;
    $redisInfo->{DATA_PATH}  = $dbFilePath;

    #服务名, 要根据实际来设置
    $redisInfo->{SERVER_NAME}   = $procInfo->{HOST_NAME};

    my @data = ($redisInfo);

    #集群信息
    my $clusterInfo;
    if (@memberPeers) {
        my @sortedMemberPeers = sort(@memberPeers);
        my $primaryAddr       = $sortedMemberPeers[0];
        my ( $primaryIp, $primaryPort ) = split( ':', $primaryAddr, 2 );

        my $clusterInfo = {
            _OBJ_CATEGORY => CollectObjCat->get('CLUSTER'),
            _OBJ_TYPE     => 'RedisCluster',
            CLUSTER_MODE  => $redisMode,
            UNIQUE_NAME   => "Redis:$primaryAddr",
            PRIMARY_IP    => $primaryIp,
            PORT          => $primaryPort,
            MEMBER_PEER   => \@sortedMemberPeers
        };
        push( @data, $clusterInfo );
    }

    return @data;
}

1;
