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

sub getUser {
    my ($self) = @_;

    my $postgresql = $self->{postgresql};
    my @users;
    my $rows = $postgresql->query(
        sql     => q{select distinct rolname FROM pg_authid},
        verbose => $self->{isVerbose}
    );

    #rolname
    #----------
    #postgres
    #(1 row)
    my @users;
    foreach my $row (@$rows) {
        if ( $row->{rolname} ne '' ) {
            push( @users, $row->{rolname} );
        }
    }

    #TODO: How to get user default table space, 老的是有有问题的，没有迁移过来

    return \@users;
}

sub parseCommandOpts {
    my ( $self, $command ) = @_;

    #/usr/bin/postgres -D /var/lib/pgsql/data -p 5432
    my $opts = {};
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
    $postgresqlInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');

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
    $postgresqlInfo->{MON_PORT}     = $port;
    $postgresqlInfo->{PORTS}        = $ports;

    my $verOut = $self->getCmdOut( "'$postgresqlPath' --version", $osUser );
    my $version;
    if ( $verOut =~ /([\d\.]+)/s ) {
        $version = $1;
    }
    $postgresqlInfo->{VERSION} = $version;

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

    my $rows;
    $rows = $postgresql->query(
        sql     => 'select datname from pg_database;',
        verbose => $self->{isVerbose}
    );

    my @dbNames = ();
    foreach my $row (@$rows) {
        my $dbName = $row->{datname};
        push(
            @dbNames,
            {
                _OBJ_CATEGORY => CollectObjCat->get('DB'),
                _OBJ_TYPE     => 'Postgresql-DB',
                NAME          => $dbName,
                PRIMARY_IP    => $bizIp,
                VIP           => $vip,
                PORT          => $port,
                SSL_PORT      => undef,
                SERVICE_ADDR  => "$vip:$port"
            }
        );
    }
    $postgresqlInfo->{DATABASES} = \@dbNames;

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

    return $postgresqlInfo;
}

1;
