#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package PostgresqlCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Socket;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use PostgresqlExec;

#需要权限：
#CONNECT 权限
#pg_authid只读
#pg_database只读

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps => ['\b(postgres|postmaster).*-D.*']    #正则表达是匹配ps输出
    };
}

sub init {
    my ($self) = @_;
    $self->{dbUsers} = {};
    return;
}

sub getUsers {
    my ( $self, $dbName ) = @_;

    my $objCat = 'DBINS';
    if ( defined($dbName) and $dbName ne '' ) {
        $objCat = 'DB';
    }

    my $postgresql = $self->{postgresql};
    my @users;
    my $rows = $postgresql->query(
        sql     => q{select usename FROM pg_user},
        verbose => $self->{isVerbose}
    );

    #usename
    #----------
    #postgres
    #(1 row)
    my @users;
    foreach my $row (@$rows) {
        if ( $row->{usename} ne '' ) {
            push(
                @users,
                {
                    _OBJ_CATEGORY => CollectObjCat->get($objCat),
                    _OBJ_TYPE     => 'DB-USER',
                    NAME          => $row->{usename}
                }
            );
        }
    }

    #TODO: How to get user default table space, 老的是有有问题的，没有迁移过来

    return \@users;
}

sub parseCommandOpts {
    my ( $self, $command ) = @_;

    #/usr/bin/postgres -D /var/lib/pgsql/data -p 5432
    my $opts  = {};
    my @items = split( /\s+-/, $command );
    $opts->{postgresqlPath} = $items[0];
    if ( $items[0] =~ /^(.*?)\/bin\/(postgres|postmaster)/ ) {
        $opts->{postgresqlHome} = $1;
    }

    for ( my $i = 1 ; $i < scalar(@items) ; $i++ ) {
        my $item = $items[$i];
        my ( $key, $val ) = split( ' ', $item );
        $opts->{$key} = $val;
    }

    return $opts;
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
    my $connInfo         = $procInfo->{CONN_INFO};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $postgresqlInfo = {};
    $postgresqlInfo->{MGMT_IP}       = $procInfo->{MGMT_IP};
    $postgresqlInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');
    $postgresqlInfo->{_MULTI_PROC}   = 1;

    #设置此采集到的对象对象类型，可以是：CollectObjCat->get('INS')，CollectObjCat->get('DBINS')，CollectObjCat::OS

    my $osUser         = $procInfo->{USER};
    my $command        = $procInfo->{COMMAND};
    my $opts           = $self->parseCommandOpts($command);
    my $postgresqlHome = $opts->{postgresqlHome};
    my $postgresqlPath = $opts->{postgresqlPath};

    $postgresqlInfo->{INSTALL_PATH} = $postgresqlHome;

    my ( $ports, $port ) = $self->getPortFromProcInfo($postgresqlInfo);

    if ( defined( $opts->{'p'} ) ) {
        $port = int( $opts->{'p'} );
    }

    if ( $port == 65535 ) {
        print("WARN: Can not determine Postgresql listen port.\n");
        return undef;
    }

    my $pFinder = $self->{pFinder};
    my ( $bizIp, $vip ) = $pFinder->predictBizIp( $connInfo, $port );

    $postgresqlInfo->{PRIMARY_IP}   = $bizIp;
    $postgresqlInfo->{VIP}          = $vip;
    $postgresqlInfo->{PORT}         = $port;
    $postgresqlInfo->{SERVICE_ADDR} = "$vip:$port";
    $postgresqlInfo->{SSL_PORT}     = undef;

    my $verOut = $self->getCmdOut( "'$postgresqlPath' --version", $osUser );
    my $version;
    if ( $verOut =~ /([\d\.]+)/s ) {
        $version = $1;
    }
    $postgresqlInfo->{VERSION} = $version;
    if ( $version =~ /(\d+)/ ) {
        $postgresqlInfo->{MAJOR_VERSION} = "PostgreSQL$1";
    }

    my $host       = '127.0.0.1';
    my $postgresql = PostgresqlExec->new(
        psqlHome => $postgresqlHome,
        osUser   => $osUser,
        username => $self->{defaultUsername},
        password => $self->{defaultPassword},
        host     => $host,
        port     => $port
    );
    $self->{$postgresql} = $postgresql;

    #获取用户
    my $rows;
    my @users;
    my $rows = $postgresql->query(
        sql     => q{select usename FROM pg_user},
        verbose => $self->{isVerbose}
    );
    foreach my $row (@$rows) {
        if ( $row->{usename} ne '' ) {
            push( @users, $row->{usename} );
        }
    }

    #获取数据目录
    my $pgdata;
    $rows = $postgresql->query(
        sql     => 'SHOW data_directory;',
        verbose => $self->{isVerbose}
    );
    foreach my $row (@$rows) {
        $pgdata = $row->{data_directory};
        last;
    }

    #获取DB编码
    my $charset;
    $rows = $postgresql->query(
        sql     => 'SELECT pg_encoding_to_char(encoding) AS encoding FROM pg_database WHERE datname = current_database();',
        verbose => $self->{isVerbose}
    );
    foreach my $row (@$rows) {
        $charset = $row->{encoding};
        last;
    }
    $postgresqlInfo->{CHARSET} = $charset;

    #获取DB主从角色
    my $mode;
    $rows = $postgresql->query(
        sql     => 'select pg_is_in_recovery();',
        verbose => $self->{isVerbose}
    );
    foreach my $row (@$rows) {
        $mode = $row->{pg_is_in_recovery};
        last;
    }
    if ( $mode eq 't' ) {
        $postgresqlInfo->{CLUSTER_MODE} = 'Master-Slave';
        $postgresqlInfo->{CLUSTER_ROLE}      = 'Slave';
    }
    elsif ( $mode eq 'f' ) {
        my $isCluster   = 0;
        my $pgConfLines = $self->getFileLines("$pgdata/postgresql.conf");
        foreach my $line (@$pgConfLines) {
            if ( $line =~ /^cluster_name\s*=\s*/ ) {
                $isCluster = 1;
                last;
            }
        }

        if ($isCluster) {
            $postgresqlInfo->{CLUSTER_MODE} = 'Master-Slave';
            $postgresqlInfo->{CLUSTER_ROLE}      = 'Master';
        }
        else {
            $postgresqlInfo->{CLUSTER_MODE} = 'Single';
            $postgresqlInfo->{CLUSTER_ROLE}      = '';
        }
    }

    #vip是浮动IP，bizIp是固定IP，predictBizIp对于Linux做了修正，secondary IP优先作为VIP
    # if ( $postgresqlInfo->{CLUSTER_ROLE} eq 'Master' ) {
    #     my $ip_return = `ip a`;
    #     my @lines     = split(/\n/, $ip_return);    # 将输出按行拆分成数组
    #     foreach my $line (@lines) {
    #         if ( $line =~ /secondary/ ) {
    #             if ( $line =~ /(\d+\.\d+\.\d+\.\d+)/ ) {    # 修正正则表达式
    #                 $bizIp = $1;
    #                 last;
    #             }
    #         }
    #     }
    # }

    #DB实例
    my @dbInstances;
    if ( $postgresqlInfo->{CLUSTER_MODE} eq 'Single' ) {
        my $ins;
        $ins->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');
        $ins->{_OBJ_TYPE}     = 'Postgresql';
        $ins->{INSTANCE_NAME} = $postgresqlInfo->{INSTANCE_NAME};
        $ins->{MGMT_IP}       = $postgresqlInfo->{MGMT_IP};
        $ins->{PORT}          = $postgresqlInfo->{PORT};
        push( @dbInstances, $ins );
    }
    else {
        my $ins;
        if ( $postgresqlInfo->{CLUSTER_ROLE} eq 'Master' ) {
             my @ipAddrs = ();
            my $pgHbaConfLines = $self->getFileLines("$pgdata/pg_hba.conf");
            foreach my $line (@$pgHbaConfLines){
                if ( $line =~ /^\s*host\s+replication\s+replicator\s+(\d+\.\d+\.\d+\.\d+)\/\d+\s+trust\s*$/ ) {
                    my $ip_address = $1;
                    push (@ipAddrs, $ip_address);
                }
            }

            foreach my $ip (@ipAddrs) {

                $ins->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');
                $ins->{_OBJ_TYPE}     = 'Postgresql';
                $ins->{INSTANCE_NAME} = $postgresqlInfo->{INSTANCE_NAME};
                $ins->{MGMT_IP}       = $ip;
                $ins->{PORT}          = $postgresqlInfo->{PORT};
                push (@dbInstances, $ins);
            }

        }
    }

    #获取所有的DB库
    $rows = $postgresql->query(
        sql     => 'select datname from pg_database;',
        verbose => $self->{isVerbose}
    );

    my @dbs = ();
    foreach my $row (@$rows) {
        my $dbName      = $row->{datname};
        my @dbUserInfos = ();
        my @dbConns     = ();

        foreach my $dbUser (@users) {
            push(
                @dbUserInfos,
                {
                    _OBJ_CATEGORY => CollectObjCat->get('DB'),
                    _OBJ_TYPE     => 'DB-USER',
                    NAME          => $dbUser
                }
            );

            push(
                @dbConns,
                {
                    _OBJ_CATEGORY => CollectObjCat->get('DB'),
                    _OBJ_TYPE     => 'DB-CONNECT',
                    SERVICE_NAME  => $dbName,
                    USER_NAME     => $dbUser
                }
            );
        }

        push(
            @dbs,
            {
                _OBJ_CATEGORY => CollectObjCat->get('DB'),
                _OBJ_TYPE     => 'Postgresql-DB',
                NAME          => $dbName,
                CLUSTER_MODE  => $postgresqlInfo->{CLUSTER_MODE},
                VERSION       => $postgresqlInfo->{VERSION},
                CHARSET       => $postgresqlInfo->{CHARSET},
                PRIMARY_IP    => $bizIp,
                VIP           => $vip,
                PORT          => $port,
                USERS         => \@dbUserInfos,
                CONNECTIONS   => \@dbConns,
                SSL_PORT      => undef,
                SERVICE_ADDR  => "$vip:$port",
                INSTANCES     => \@dbInstances
            }
        );
    }
    if ( $postgresqlInfo->{CLUSTER_MODE} eq 'Single' or $postgresqlInfo->{CLUSTER_ROLE} eq 'Master' ) {
        $postgresqlInfo->{DATABASES} = \@dbs;
    }
    $rows = $postgresql->query(
        sql     => q{show all},
        verbose => $self->{isVerbose}
    );

    my $results;
    foreach my $row (@$rows) {
        $results->{ $row->{name} } = $row->{setting};
    }

    if ($results) {
        $postgresqlInfo->{LISTEN_ADDRESSES}             = $results->{listen_addresses};
        $postgresqlInfo->{PORT}                         = $results->{port};
        $postgresqlInfo->{APPLICATION_NAME}             = $results->{application_name};
        $postgresqlInfo->{SERVER_VERSION}               = $results->{server_version};
        $postgresqlInfo->{DATA_DIRECTORY}               = $results->{data_directory};
        $postgresqlInfo->{CONFIG_FILE}                  = $results->{config_file};
        $postgresqlInfo->{HBA_FILE}                     = $results->{hba_file};
        $postgresqlInfo->{IDENT_FILE}                   = $results->{ident_file};
        $postgresqlInfo->{MAX_CONNECTIONS}              = $results->{max_connections};
        $postgresqlInfo->{SHARED_BUFFERS}               = $results->{shared_buffers};
        $postgresqlInfo->{WORK_MEM}                     = $results->{work_mem};
        $postgresqlInfo->{EFFECTIVE_CACHE_SIZE}         = $results->{effective_cache_size};
        $postgresqlInfo->{MAINTENANCE_WORK_MEM}         = $results->{maintenance_work_mem};
        $postgresqlInfo->{WAL_BUFFERS}                  = $results->{wal_buffers};
        $postgresqlInfo->{WAL_LEVEL}                    = $results->{wal_level};
        $postgresqlInfo->{CHECKPOINT_SEGMENTS}          = $results->{checkpoint_segments};
        $postgresqlInfo->{CHECKPOINT_COMPLETION_TARGET} = $results->{checkpoint_completion_target};
        $postgresqlInfo->{COMMIT_DELAY}                 = $results->{commit_delay};
        $postgresqlInfo->{COMMIT_SIBLINGS}              = $results->{commit_siblings};
        $postgresqlInfo->{CLUSTER_NAME}                 = $results->{cluster_name};
        $postgresqlInfo->{DATESTYLE}                    = $results->{datestyle};
        $postgresqlInfo->{LC_TIME}                      = $results->{lc_time};
        $postgresqlInfo->{DEFAULT_TEXT_SEARCH_CONFIG}   = $results->{default_text_search_config};
        $postgresqlInfo->{MAX_WORKER_PROCESSES}         = $results->{max_worker_processes};
        $postgresqlInfo->{MAX_LOCKS_PER_TRANSACTION}    = $results->{max_locks_per_transaction};
        $postgresqlInfo->{TRACK_COMMIT_TIMESTAMP}       = $results->{track_commit_timestamp};
        $postgresqlInfo->{MAX_PREPARED_TRANSACTIONS}    = $results->{max_prepared_transactions};
        $postgresqlInfo->{HOT_STANDBY}                  = $results->{hot_standby};
        $postgresqlInfo->{MAX_REPLICATION_SLOTS}        = $results->{max_replication_slots};
        $postgresqlInfo->{WAL_LOG_HINTS}                = $results->{wal_log_hints};
        $postgresqlInfo->{MAX_WAL_SENDERS}              = $results->{max_wal_senders};
    }

#############################

    #服务名, 要根据实际来设置
    $postgresqlInfo->{SERVER_NAME}   = $procInfo->{HOST_NAME};
    $postgresqlInfo->{INSTANCE_NAME} = '-';
    my @collectSet = ();
    push( @collectSet, $postgresqlInfo );
    if ( defined( $postgresqlInfo->{DATABASES} ) ) {
        if ( @{ $postgresqlInfo->{DATABASES} } ) {
            push( @collectSet, @{ $postgresqlInfo->{DATABASES} } );
        }
    }
    return @collectSet;

}
1;
