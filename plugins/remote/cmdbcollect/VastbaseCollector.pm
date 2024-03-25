#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package VastbaseCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Socket;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use VastbaseExec;

#需要权限：
#CONNECT 权限
#vastbase_authid只读
#vastbase_database只读

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps => ['\bvastbase']    #正则表达是匹配ps输出
    };
}

sub getUser {
    my ($self) = @_;

    my $vastbase = $self->{vastbase};
    my @users;
    my $rows = $vastbase->query(
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

sub getSchema {
    my ( $self, $osUser, $host, $port, $vastbaseHome, $dbName, $userName ) = @_;
    my $vastbaseDB = VastbaseExec->new(
        vsqlHome => $vastbaseHome,
        osUser   => $osUser,
        dbname   => $dbName,
        username => $self->{defaultUsername},
        password => $self->{defaultPassword},
        host     => $host,
        port     => $port
    );
    my $rows = $vastbaseDB->query(
        sql     => q{select schema_name from information_schema.schemata where schema_owner='$userName'},
        verbose => $self->{isVerbose}
    );

    my @schemas;
    foreach my $row (@$rows) {
        if ( $row->{schema_name} ne '' ) {
            push( @schemas, $row->{schema_name} );
        }
    }
    return \@schemas;
}

sub getSearchPath {
    my ( $self, $osUser, $host, $port, $vastbaseHome, $dbName, $userName ) = @_;
    my $vastbaseDB = VastbaseExec->new(
        vsqlHome => $vastbaseHome,
        osUser   => $osUser,
        dbname   => $dbName,
        username => $self->{defaultUsername},
        password => $self->{defaultPassword},
        host     => $host,
        port     => $port
    );
    my $rows = $vastbaseDB->query(
        sql     => q{select setting from pg_settings where name='search_path'},
        verbose => $self->{isVerbose}
    );

    my $searchPath;
    foreach my $row (@$rows) {
        if ( $row->{setting} ne '' ) {
            $searchPath = $row->{setting};
        }
    }
    return $searchPath;
}

sub parseCommandOpts {
    my ( $self, $command ) = @_;

    #/usr/bin/postgres -D /var/lib/pgsql/data -p 5432
    my $opts  = {};
    my @items = split( /\s+-/, $command );
    $opts->{vastbasePath} = $items[0];
    if ( $items[0] =~ /^(.*?)\/bin\/(vastbase)/ ) {
        $opts->{vastbaseHome} = $1;
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

    my $vastbaseInfo = {};
    $vastbaseInfo->{MGMT_IP}       = $procInfo->{MGMT_IP};
    $vastbaseInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');
    $vastbaseInfo->{_MULTI_PROC}   = 1;

    #设置此采集到的对象对象类型，可以是：CollectObjCat->get('INS')，CollectObjCat->get('DBINS')，CollectObjCat::OS

    my $osUser       = $procInfo->{USER};
    my $command      = $procInfo->{COMMAND};
    my $opts         = $self->parseCommandOpts($command);
    my $vastbaseHome = $opts->{vastbaseHome};
    my $vastbasePath = $opts->{vastbasePath};

    $vastbaseInfo->{INSTALL_PATH} = $vastbaseHome;

    my ( $ports, $port ) = $self->getPortFromProcInfo($vastbaseInfo);

    if ( defined( $opts->{'p'} ) ) {
        $port = int( $opts->{'p'} );
    }

    if ( $port == 65535 ) {
        print("WARN: Can not determine Postgresql listen port.\n");
        return undef;
    }

    my $pFinder = $self->{pFinder};
    my ( $bizIp, $vip ) = $pFinder->predictBizIp( $connInfo, $port );

    $vastbaseInfo->{PRIMARY_IP}   = $bizIp;
    $vastbaseInfo->{VIP}          = $vip;
    $vastbaseInfo->{PORT}         = $port;
    $vastbaseInfo->{SERVICE_ADDR} = "$vip:$port";
    $vastbaseInfo->{SSL_PORT}     = undef;

    my $verOut = $self->getCmdOut( "'$vastbasePath' --version", $osUser );
    my $version;
    if ( $verOut =~ /([\d\.]+)/s ) {
        $version = $1;
    }
    $vastbaseInfo->{VERSION} = $version;
    if ( $version =~ /(\d+)/ ) {
        $vastbaseInfo->{MAJOR_VERSION} = "vastbase$1";
    }

    my $host     = '127.0.0.1';
    my $vastbase = VastbaseExec->new(
        vsqlHome => $vastbaseHome,
        osUser   => $osUser,
        dbname   => 'vastbase',
        username => $self->{defaultUsername},
        password => $self->{defaultPassword},
        host     => $host,
        port     => $port
    );
    $self->{$vastbase} = $vastbase;

    my $rows;
    $rows = $vastbase->query(
        sql     => q{select pd.datname,pu.usename,pd.datcompatibility,pg_encoding_to_char(pd.encoding) as charset from pg_catalog.pg_database pd left join pg_user pu on pd.datdba = pu.usesysid where datname not in ('template1','template0','vastbase','postgres');},
        verbose => $self->{isVerbose}
    );

    my @databases = ();
    foreach my $row (@$rows) {
        my $dbName   = $row->{datname};
        my $userName = $row->{usename};

        my $schemas    = $self->getSchema( $osUser, $host, $port, $vastbaseHome, $dbName, $userName );
        my $searchPath = $self->getSearchPath( $osUser, $host, $port, $vastbaseHome, $dbName, $userName );
        push(
            @databases,
            {
                _OBJ_CATEGORY         => CollectObjCat->get('DB'),
                _OBJ_TYPE             => 'Vastbase-DB',
                NAME                  => $dbName,
                PRIMARY_IP            => $bizIp,
                VIP                   => $vip,
                PORT                  => $port,
                SSL_PORT              => undef,
                SERVICE_ADDR          => "$vip:$port",
                COMPATIBILITY         => $row->{datcompatibility},
                DEFAULT_CHARACTER_SET => $row->{charset},
                SCHEMA                => join( ",", @$schemas ),
                SEARCHPATH            => $searchPath,
                USERS                 => [
                    {
                        _OBJ_CATEGORY => CollectObjCat->get('DB'),
                        _OBJ_TYPE     => 'DB-USER',
                        NAME          => $userName
                    }
                ],
                CONNECTION => [
                    {
                        _OBJ_CATEGORY => CollectObjCat->get('DB'),
                        _OBJ_TYPE     => 'DB-CONNECT',
                        USER_NAME     => $userName,
                        SERVICE_NAME  => $dbName
                    }
                ],
                INSTANCES => [
                    {
                        _OBJ_CATEGORY => CollectObjCat->get('DBINS'),
                        _OBJ_TYPE     => 'Vastbase',
                        INSTANCE_NAME => $vastbaseInfo->{INSTANCE_NAME},
                        MGMT_IP       => $vastbaseInfo->{MGMT_IP},
                        PORT          => $vastbaseInfo->{PORT}
                    }
                ]
            }
        );
    }
    $vastbaseInfo->{DATABASES} = \@databases;

    $rows = $vastbase->query(
        sql     => q{show all},
        verbose => $self->{isVerbose}
    );

    my $results;
    foreach my $row (@$rows) {
        $results->{ $row->{name} } = $row->{setting};
    }

    if ($results) {
        $vastbaseInfo->{LISTEN_ADDRESSES}             = $results->{listen_addresses};
        $vastbaseInfo->{PORT}                         = $results->{port};
        $vastbaseInfo->{APPLICATION_NAME}             = $results->{application_name};
        $vastbaseInfo->{SERVER_VERSION}               = $results->{server_version};
        $vastbaseInfo->{DATA_DIRECTORY}               = $results->{data_directory};
        $vastbaseInfo->{CONFIG_FILE}                  = $results->{config_file};
        $vastbaseInfo->{HBA_FILE}                     = $results->{hba_file};
        $vastbaseInfo->{IDENT_FILE}                   = $results->{ident_file};
        $vastbaseInfo->{MAX_CONNECTIONS}              = $results->{max_connections};
        $vastbaseInfo->{SHARED_BUFFERS}               = $results->{shared_buffers};
        $vastbaseInfo->{WORK_MEM}                     = $results->{work_mem};
        $vastbaseInfo->{EFFECTIVE_CACHE_SIZE}         = $results->{effective_cache_size};
        $vastbaseInfo->{MAINTENANCE_WORK_MEM}         = $results->{maintenance_work_mem};
        $vastbaseInfo->{WAL_BUFFERS}                  = $results->{wal_buffers};
        $vastbaseInfo->{WAL_LEVEL}                    = $results->{wal_level};
        $vastbaseInfo->{CHECKPOINT_SEGMENTS}          = $results->{checkpoint_segments};
        $vastbaseInfo->{CHECKPOINT_COMPLETION_TARGET} = $results->{checkpoint_completion_target};
        $vastbaseInfo->{COMMIT_DELAY}                 = $results->{commit_delay};
        $vastbaseInfo->{COMMIT_SIBLINGS}              = $results->{commit_siblings};
        $vastbaseInfo->{CLUSTER_NAME}                 = $results->{cluster_name};
        $vastbaseInfo->{DATESTYLE}                    = $results->{datestyle};
        $vastbaseInfo->{LC_TIME}                      = $results->{lc_time};
        $vastbaseInfo->{DEFAULT_TEXT_SEARCH_CONFIG}   = $results->{default_text_search_config};
        $vastbaseInfo->{MAX_WORKER_PROCESSES}         = $results->{max_worker_processes};
        $vastbaseInfo->{MAX_LOCKS_PER_TRANSACTION}    = $results->{max_locks_per_transaction};
        $vastbaseInfo->{TRACK_COMMIT_TIMESTAMP}       = $results->{track_commit_timestamp};
        $vastbaseInfo->{MAX_PREPARED_TRANSACTIONS}    = $results->{max_prepared_transactions};
        $vastbaseInfo->{HOT_STANDBY}                  = $results->{hot_standby};
        $vastbaseInfo->{MAX_REPLICATION_SLOTS}        = $results->{max_replication_slots};
        $vastbaseInfo->{WAL_LOG_HINTS}                = $results->{wal_log_hints};
        $vastbaseInfo->{MAX_WAL_SENDERS}              = $results->{max_wal_senders};
    }

#############################

    #服务名, 要根据实际来设置
    $vastbaseInfo->{SERVER_NAME}   = $procInfo->{HOST_NAME};
    $vastbaseInfo->{INSTANCE_NAME} = '-';

    my @collectSet = ();
    push( @collectSet, $vastbaseInfo );
    push( @collectSet, @databases );

    return @collectSet;
}

1;
