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
use File::Spec;
use File::Basename;
use IO::File;
use File::Copy;
use CollectObjCat;
use RedisExec;

sub getConfig {
    return {
        regExps => ['\bredis-server\s'],         #正则表达是匹配ps输出
        psAttrs => { COMM => 'redis-server' }    #ps的属性的精确匹配
    };
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
    my $osUser           = $procInfo->{USER};
    my $redisInfo        = {};
    $redisInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');

    #设置此采集到的对象对象类型，可以是：CollectObjCat->get('INS')，CollectObjCat->get('DBINS')，CollectObjCat::OS
    my $command  = $procInfo->{COMMAND};
    my $exePath  = $procInfo->{EXECUTABLE_FILE};
    my $binPath  = dirname($exePath);
    my $homePath = dirname($binPath);

    #Redis server v=3.2.12 sha=00000000:0 malloc=jemalloc-3.6.0 bits=64 build=7897e7d0e13773f
    my $verInfo = $self->getCmdOut(qq{"$exePath" -v});
    if ( $verInfo =~ /v=([\d\.]+)/ ) {
        $redisInfo->{VERSION} = $1;
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

    my $cliFile = File::Spec->catfile( $binPath, "redis-cli" );
    $redisInfo->{INSTALL_PATH} = $homePath;
    $redisInfo->{CONFIG_FILE}  = $configFile;

    #检查是否装了reds-cli
    if ( not -e $cliFile and -e "$FindBin::Bin/redis-cli" ) {

        #需要改为自动到介质中心下载
        copy( "$FindBin::Bin/redis-cli", $binPath );
        chmod( 0755, "$binPath/redis-cli" );
    }

    my ( $ports, $port ) = $self->getPortFromProcInfo($redisInfo);

    #配置文件
    $self->parseConfig( $configFile, $redisInfo );

    if ( defined( $redisInfo->{PORT} ) ) {
        $port = int( $redisInfo->{PORT} );
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
    $redisInfo->{MON_PORT}       = $port;
    $redisInfo->{ADMIN_PORT}     = $port;
    $redisInfo->{ADMIN_SSL_PORT} = $port;

    #如果redis存在哨兵进程，则通过哨兵端口进行连接
    my $cliPort;
    my $sentinelLsnInfo = $self->getCmdOut(qq{netstat -nap |grep $port|grep redis-sentine|grep LISTEN | awk '{print \$4}'});
    if ( $sentinelLsnInfo =~ /:(\d+)\b/ ) {
        $cliPort = int($1);
        print("INFO: Connect info by redis sentinel, port:$cliPort.\n");
    }

    my $auth;
    if ( not defined($cliPort) ) {
        $cliPort = $port;

        $auth = $self->{defaultPassword};
        if ( not defined($auth) ) {
            $auth = $redisInfo->{REQUIREPASS};
            if ( not defined($auth) ) {
                $auth = $redisInfo->{MASTERAUTH};
            }
        }
    }

    my $host  = '127.0.0.1';
    my $redis = RedisExec->new(
        redisHome => $binPath,
        auth      => $auth,
        host      => $host,
        port      => $cliPort
    );
    $self->{redis} = $redis;

    my ( $status, $info ) = $redis->query(
        sql     => 'info',
        verbose => $self->{isVerbose}
    );
    $redisInfo->{EXECUTABLE}       = $info->{EXECUTABLE};
    $redisInfo->{MULTIPLEXING_API} = $info->{MULTIPLEXING_API};
    $redisInfo->{RUN_ID}           = $info->{RUN_ID};
    my $mode        = $info->{REDIS_MODE};
    my $role        = $info->{ROLE};
    my $master_host = $info->{MASTER_HOST};
    my $master_port = $info->{MASTER_PORT};
    $redisInfo->{CLUSTER_MODE} = undef;
    $redisInfo->{CLUSTER_ROLE} = undef;
    $redisInfo->{IS_CLUSTER}   = 0;

    if ( $mode eq 'cluster' ) {
        $redisInfo->{CLUSTER_MODE} = 'Master-Slave';
        $redisInfo->{CLUSTER_ROLE} = $role;
        $redisInfo->{IS_CLUSTER}   = 1;
        if ( $role eq 'slave' ) {
            $redisInfo->{MASTER_IPS} = $master_host . ":" . $master_port;
        }
        else {
            my $cns       = int( $info->{CONNECTED_SLAVES} );
            my @slaveInfo = ();
            for ( $a = 0 ; $a < $cns ; $a = $a + 1 ) {
                my $slave = $info->{ 'SLAVE' . $a };
                $slave =~ s/'slave'$a//g;
                my @slave_tmp = split( /,/, $slave );
                my $slave_host;
                my $slave_port;
                foreach my $st (@slave_tmp) {
                    if ( $st =~ /ip/ig ) {
                        my @st_tmp = split( /=/, $st );
                        $slave_host = $st_tmp[1];
                    }
                    if ( $st =~ /port/ig ) {
                        my @st_tmp = split( /=/, $st );
                        $slave_port = $st_tmp[1];
                    }
                }
                push( @slaveInfo, { VALUE => $slave_host . ":" . $slave_port } );
            }
            $redisInfo->{SLAVE_NODES} = \@slaveInfo;
        }
    }

    #服务名, 要根据实际来设置
    $redisInfo->{INSTANCE_NAME} = $procInfo->{HOST_NAME};
    $redisInfo->{SERVER_NAME}   = $procInfo->{HOST_NAME};

    return $redisInfo;
}

#配置文件
sub parseConfig {
    my ( $self, $configFile, $redisInfo ) = @_;
    my $configData = $self->getFileLines($configFile);

    #只取定义的配置
    my $filter = {
        "dbfilename"     => 1,
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

        my @values = split( /\s+/, $line );
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

1;
