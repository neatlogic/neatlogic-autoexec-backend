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
use Sys::Hostname;
use CollectObjType;
use RedisExec;
use Data::Dumper;

sub getConfig {
    return {
        regExps => ['\bredis-server\s'],         #正则表达是匹配ps输出
        psAttrs => { COMM => 'redis-server' }    #ps的属性的精确匹配
    };
}

sub getPK {
    my ($self) = @_;
    return {
        #默认KEY用类名去掉Collector，对应APP_TYPE属性值
        #配置值就是作为PK的属性名
        $self->{defaultAppType} => [ 'INBOUND_IP', 'PORT', ]

            #如果返回的是多种对象，需要手写APP_TYPE对应的PK配置
    };
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
sub collect {
    my ($self) = @_;

    $self->{isVerbose} = 0;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    my $osUser           = $procInfo->{USER};
    my $redisInfo        = {};
    $redisInfo->{OBJECT_TYPE} = $CollectObjType::DB;

    #设置此采集到的对象对象类型，可以是：CollectObjType::APP，CollectObjType::DB，CollectObjType::OS
    my $command    = $procInfo->{COMMAND};
    my $exePath    = $procInfo->{EXECUTABLE_FILE};
    my $basePath   = dirname($exePath);
    my $configFile = File::Spec->catfile( $basePath, "redis.conf" );
    my $cliFile    = File::Spec->catfile( $basePath, "redis-cli" );
    $redisInfo->{INSTALL_PATH} = $basePath;
    $redisInfo->{CONFIG_FILE}  = $configFile;

    #检查是否装了reds-cli
    if ( !-e "$cliFile" ) {
        copy( 'redis-cli', $basePath );
        my @uname  = uname();
        my $ostype = $uname[0];
        if ( $ostype ne 'Windows' ) {
            system("chmod 755 $basePath/redis-cli");
        }
    }

    #配置文件
    parseConfig( $self, $configFile, $redisInfo );

    my $port = $redisInfo->{'PORT'};
    my $host = '127.0.0.1';
    my $auth = $redisInfo->{'REQUIREPASS'};
    if ( not defined($auth) ) {
        $auth = $redisInfo->{MASTERAUTH};
    }

    $redisInfo->{PORT}           = $port;
    $redisInfo->{SSL_PORT}       = $port;
    $redisInfo->{MON_PORT}       = $port;
    $redisInfo->{ADMIN_PORT}     = $port;
    $redisInfo->{ADMIN_SSL_PORT} = $port;

    my $redis = RedisExec->new(
        redisHome => $basePath,
        auth      => $auth,
        host      => $host,
        port      => $port
    );
    $self->{redis} = $redis;

    my ( $status, $info ) = $redis->query(
        sql     => 'info',
        verbose => $self->{isVerbose}
    );
    $redisInfo->{VERSION}          = $info->{REDIS_VERSION};
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
            my @slave_arr = ();
            for ( $a = 0 ; $a < $cns ; $a = $a + 1 ) {
                my $slave = $info->{ 'SLAVE' . $a };
                $slave =~ s/'slave'$a//g;
                my @slave_tmp = str_split( $slave, ',' );
                my $slave_host;
                my $slave_port;
                foreach my $st (@slave_tmp) {
                    if ( $st =~ /ip/ig ) {
                        my @st_tmp = str_split( $st, '=' );
                        $slave_host = $st_tmp[1];
                    }
                    if ( $st =~ /port/ig ) {
                        my @st_tmp = str_split( $st, '=' );
                        $slave_port = $st_tmp[1];
                    }
                }
                push( @slave_arr, $slave_host . ":" . $slave_port );
            }
            $redisInfo->{SLAVE_IPS} = \@slave_arr;
        }
    }

    #服务名, 要根据实际来设置
    $redisInfo->{SERVER_NAME} = $procInfo->{APP_TYPE};

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
        chomp($line);
        $line =~ s/^\s+//g;
        $line =~ ~s/\s+$//g;
        if ( $line =~ /^#/ or $line eq '' ) {
            next;
        }

        my @values = str_split( $line, '\s+' );
        if ( scalar(@values) > 1 ) {
            my $key   = str_trim( @values[0] );
            my $value = str_trim( @values[1] );
            $value =~ s/['"]//g;
            if ( defined( $filter->{$key} ) ) {
                $redisInfo->{ uc($key) } = $value;
            }
        }
    }
}

sub str_split {
    my ( $str, $separator ) = @_;
    my @values = split( /$separator/, $str );
    return @values;
}

sub str_trim {
    my ($str) = @_;
    $str =~ s/^\s+|\s+$//g;
    return $str;
}

1;
