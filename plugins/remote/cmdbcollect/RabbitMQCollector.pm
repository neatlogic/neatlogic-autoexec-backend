#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package RabbitMQCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);
use JSON;
use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use XML::MyXML qw(xml_to_object);
use CollectObjCat;
use Socket;

sub getConfig {
    return {
        regExps => ['\brabbitmq\b'],        #正则表达是匹配ps输出
        psAttrs => { COMM => 'beam.smp' }
    };
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo  = $self->{procInfo};
    my $envMap    = $procInfo->{ENVIRONMENT};
    my $listenMap = $procInfo->{CONN_INFO}->{LISTEN};
    my $mainPid   = $procInfo->{PID};
    my $mgmtIp    = $procInfo->{MGMT_IP};

    #/app/rabbitmq/erlang/lib/erlang/erts-10.7/bin/beam.smp -W w -A 64 -MBas ageffcbf -MHas ageffcbf -MBlmbcs 512 -MHlmbcs 512 -MMmcs 30 -P 1048576 -t 5000000 -stbt db -zdbbl 128000 -K true -- -root /app/rabbitmq/erlang/lib/erlang -progname erl -- -home /app/cfsp -- -pa/app/rabbitmq/rabbitmq_home/ebin -noshell -noinput -s rabbit boot -sname ra bbit@czcszjj1 -boot start_sasl -kernel_inet_default_connect_options [{nodelay,true}]-sasl errlog_type error -sasl sasl_error_logger false -rabbit lager_log_root "/app/rabbitmq/rabbitmq_home/logs"- rabbit lager_default_file "/app/rabbitmq/rabbitmq_home/logs/rabbit@czcszjj1.log" -rabbit lager_upgrade_file "/app/rabbitmq/rabbitmq_home/logs/rabbit@czcszjj1_upgrade.log" -rabbit feature_flags_file "/app/rabbitmq/rabbitmq_home/var/lib/rabbitmq/mnesia/rabbit@czcszjj1-feature_flags" -rabbit_ enabled_plugins_file "/app/rabbitmq/rabbitmq_home/etc/rabbitmq/enabled_plugins" -rabbit plugins_dir "/app/ rabbitmq/rabbitmq_home/plugins"-rabbit plugins_expand_dir"/app/rabbitmq/rabbitmq_home/var/lib/rabbitmq/mnesia/rabbit@czcszjj1-plugins-expand" -os_mon start_cpu_sup false -os_mon start_disksup fals e -os mon start_ memsup false -mnesia dir "/app/rabbitmq/rabbitmq_home/var/lib/rabbitmq/mnesia/rabbit@czcszjj1"-ra data_dir "/app/rabbitmq/rabbitmq_home/var/lib/rabbitmq/mnesia/rabbit@czcszjj1/quoru m" -kernel inet_dist_listen_min 25672 -kernel -inet_dist_listen_max 25672 -noshell -noinput --
    my $cmdLine = $procInfo->{COMMAND};

    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');
    $appInfo->{_OBJ_TYPE} = 'RabbitMQ';

    $appInfo->{EXE_PATH} = $procInfo->{EXECUTABLE_FILE};
    $appInfo->{BIN_PATH} = dirname( $procInfo->{EXECUTABLE_FILE} );

    my $workPath = readlink("/proc/$mainPid/cwd");
    my $homePath;
    if ( $cmdLine =~ /-pa\s*(\S+)\s+-/ || $cmdLine =~ /-pa\s*['"](.*?)['"]\s+-/ ) {
        $homePath = $1;
        $homePath =~ s/^["']|["']$//g;
        if ( $homePath =~ /^\.{1,2}[\/\\]/ ) {
            $homePath = Cwd::abs_path("$workPath/$homePath");
        }
    }

    if ( not defined($homePath) or $homePath eq '' ) {
        print("WARN: $cmdLine is not a rabbitmq process.\n");
        return;
    }

    $homePath = dirname($homePath);
    $appInfo->{INSTALL_PATH} = $homePath;

    my $osUser = $procInfo->{USER};
    my $version;
    my @userPw    = getpwnam($osUser);
    my $userHome  = $userPw[7];
    my $userShell = $userPw[8];


    my ( $dataDir, $configDir, $logDir );
    if ( $cmdLine =~ /-mnesia\sdir\s*(\S+)\s+-/ || $cmdLine =~ /-mnesia\sdir\s*['"](.*?)['"]\s+-/ ) {
        $dataDir = $1;
        $dataDir =~ s/^["']|["']$//g;
    }
    if ( $cmdLine =~ /-config\sdir\s*(\S+)\s+-/ || $cmdLine =~ /-config\sdir\s*['"](.*?)['"]\s+-/ ) {
        $configDir = $1;
        $configDir =~ s/^["']|["']$//g;
    }
    if ( $cmdLine =~ /-rabbit lager_log_root\sdir\s*(\S+)\s+-/ || $cmdLine =~ /-rabbit lager_log_root\sdir\s*['"](.*?)['"]\s+-/ ) {
        $logDir = $1;
        $logDir =~ s/^["']|["']$//g;
    }

    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);

    if ( $port == 65535 ) {
        print("WARN: Can not determine RabbitMQ listen port.\n");
        return undef;
    }

    if ( $port < 65535 ) {
        $appInfo->{PORT} = $port;
    }

    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    my $rbctlPath   = "$homePath/sbin/rabbitmqctl";

    my $userLines = $self->getCmdOutLines( qq{"$rbctlPath" list_users}, $osUser );
    # rabbitmqctl list_users"
    # Listing users ...
    # user tags
    # admin [administrator]
    # guest [administrator]
    # tmsmq [administrator]
    my @users = ();
    foreach my $userLine (@$userLines) {
        $userLine =~ s/^\s*|\s*$//g;
        if ( $userLine =~ /(.*?)\s+\[(.*)\]/ ) {
            my $userName = $1;
            my $userRole = $2;
            if ( $userName eq 'guest' ) {
                $appInfo->{GUEST_ENABLE} = 1;
            }
            push(
                @users,
                {
                    NAME => $userName,
                    ROLE => $userRole
                }
            );
        }
    }
    $appInfo->{USERS} = \@users;

    my $basicInfo = {};
    $basicInfo = from_json( $self->getCmdOut( qq{"$rbctlPath" status --formatter json}, $osUser ) );

    #rabbitmqctl status
    # {
    # 'net_ticktime' => 60,
    # 'uptime' => 9657718,
    # 'vm_memory_high_watermark_setting' => {
    #                                         'relative' => '0.4'
    #                                         },
    # 'rabbitmq_version' => '3.8.3',
    # 'os' => 'Linux',
    # 'log_files' => [
    #                 '/app/rabbitmq/rabbitmq_home/logs/rabbit@czcszjj1.log',
    #                 '/app/rabbitmq/rabbitmq_home/logs/rabbit@czcszjj1_upgrade.log'
    #                 ],
    # 'disk_free_limit' => 50000000,
    # 'disk_free' => '97204789248',
    # 'data_directory' => '/app/rabbitmq/rabbitmq_home/var/lib/rabbitmq/mnesia/rabbit@czcszjj1',
    # 'active_plugins' => [
    #                         'rabbitmq_management',
    #                         'rabbitmq_web_dispatch',
    #                         'rabbitmq_management_agent',
    #                         'amqp_client',
    #                         'cowboy',
    #                         'cowlib'
    #                     ],
    # 'vm_memory_high_watermark_limit' => 6287183052,
    # 'processes' => {
    #                 'limit' => 1048576,
    #                 'used' => 1258
    #                 },
    # 'pid' => 4027421,
    # 'alarms' => [],
    # 'file_descriptors' => {
    #                         'total_used' => 44,
    #                         'sockets_used' => 4,
    #                         'sockets_limit' => 58893,
    #                         'total_limit' => 65439
    #                         },
    # 'run_queue' => 1,
    # 'vm_memory_calculation_strategy' => 'rss',
    # 'config_files' => [],
    # 'memory' => {
    #                 'other_system' => 13967972,
    #                 'msg_index' => 31296,
    #                 'allocated_unused' => 22796192,
    #                 'connection_readers' => 157440,
    #                 'queue_slave_procs' => 3897164,
    #                 'other_ets' => 3485888,
    #                 'total' => {
    #                             'erlang' => 110897248,
    #                             'rss' => 135790592,
    #                             'allocated' => 133693440
    #                         },
    #                 'metrics' => 317676,
    #                 'mgmt_db' => 11958304,
    #                 'atom' => 1525929,
    #                 'connection_writers' => 49680,
    #                 'quorum_queue_procs' => 0,
    #                 'reserved_unallocated' => 2097152,
    #                 'queue_procs' => 3272024,
    #                 'quorum_ets' => 47536,
    #                 'strategy' => 'rss',
    #                 'connection_channels' => 206856,
    #                 'binary' => 2734912,
    #                 'plugins' => 13700044,
    #                 'other_proc' => 26789648,
    #                 'code' => 26033227,
    #                 'connection_other' => 1058460,
    #                 'mnesia' => 1663192
    #             },
    # 'erlang_version' => 'Erlang/OTP 22 [erts-10.7] [source] [64-bit] [smp:4:4] [ds:4:4:10] [async-threads:64]',
    # 'enabled_plugin_file' => '/app/rabbitmq/rabbitmq_home/etc/rabbitmq/enabled_plugins',
    # 'totals' => {
    #                 'virtual_host_count' => 1,
    #                 'connection_count' => 4,
    #                 'queue_count' => 240
    #             },
    # 'listeners' => [
    #                 {
    #                     'port' => 25672,
    #                     'protocol' => 'clustering',
    #                     'interface' => '[::]',
    #                     'node' => 'rabbit@czcszjj1',
    #                     'purpose' => 'inter-node and CLI tool communication'
    #                 },
    #                 {
    #                     'purpose' => 'AMQP 0-9-1 and AMQP 1.0',
    #                     'protocol' => 'amqp',
    #                     'port' => 5672,
    #                     'node' => 'rabbit@czcszjj1',
    #                     'interface' => '[::]'
    #                 },
    #                 {
    #                     'purpose' => 'HTTP API',
    #                     'node' => 'rabbit@czcszjj1',
    #                     'interface' => '[::]',
    #                     'port' => 15672,
    #                     'protocol' => 'http'
    #                 }
    #                 ]
    # };
    my $logFiles = $basicInfo->{log_files};
    if (@$logFiles) {
        $logDir = dirname( $$logFiles[0] );
    }
    if ( defined( $basicInfo->{data_directory} ) ) {
        $dataDir = $basicInfo->{data_directory};
    }

    my $configFiles = $basicInfo->{config_files};
    if (@$configFiles) {
        $configDir = dirname( $$configFiles[0] );
    }

    my $memWaterMark = $basicInfo->{vm_memory_high_watermark};
    if ( not defined($memWaterMark) ) {
        my $waterMarkSetting = $basicInfo->{vm_memory_high_watermark_setting};
        if ( defined($waterMarkSetting) ) {
            $memWaterMark = $waterMarkSetting->{relative};
        }
    }

    $appInfo->{CONFIG_PATH}       = $configDir;
    $appInfo->{DATA_PATH}         = $dataDir;
    $appInfo->{LOG_PATH}          = $logDir;
    $appInfo->{MEMORY_WATER_MARK} = $memWaterMark;

    $appInfo->{VERSION} = $basicInfo->{rabbitmq_version};
    $appInfo->{MAJOR_VERSION} = $basicInfo->{rabbitmq_version};
    
    my $erLangVer = $basicInfo->{erlang_version};
    $erLangVer =~ s/\[.*$//;
    if($erLangVer =~ /([\d\.]+)/){
        $appInfo->{ERLANG_VERSION} = $1;
    }

    if ( $self->{inspect} == 1 ) {
        $appInfo->{DISK_FREE} = int( $basicInfo->{disk_free} ) / 1000 / 1000 / 1000;
        $appInfo->{FD_LIMIT}  = int( $basicInfo->{file_descriptors}->{total_limit} );
        $appInfo->{FD_USED}   = int( $basicInfo->{file_descriptors}->{total_used} );
        my $memUsed = int( $basicInfo->{memory}->{total}->{rss} );
        $appInfo->{MEM_USED} = $memUsed / 1024 / 1024;
        my $waterMarkLimit = int( $basicInfo->{vm_memory_high_watermark_limit} );
        $appInfo->{MEM_USAGE} = $memUsed * 100 / ( $waterMarkLimit / $memWaterMark );
        $appInfo->{ALARMS}    = $basicInfo->{alarms};
    }

    my $myNodeName = '';
    my $amqPort      = $appInfo->{PORT};
    my $clusterPort  = undef;
    my $listeners = $basicInfo->{listeners};
    if ( defined($listeners) ) {
        foreach my $myLsnInfo ( @$listeners ) {
            if ( $myLsnInfo->{protocol} eq 'amqp' ) {
                $amqPort = $myLsnInfo->{port};
                $myNodeName = $myLsnInfo->{node};
                $appInfo->{PORT} = $amqPort;
            }
            elsif ( $myLsnInfo->{protocol} eq 'clustering' ) {
                $clusterPort = $myLsnInfo->{port};
                $myNodeName = $myLsnInfo->{node};
            }
        }
    }
    $appInfo->{INSTANCE_NAME} = $myNodeName;

    my $clusterInfo = {};
    $clusterInfo = from_json( $self->getCmdOut( qq{"$rbctlPath" cluster_status --formatter json}, $osUser ) );

    #rabbitmqctl cluster_status
    # {
    # 'versions' => {
    #                 'rabbit@czcszjj1' => {
    #                                         'erlang_version' => '22.3',
    #                                         'rabbitmq_version' => '3.8.3'
    #                                     },
    #                 'rabbit@czcszjj2' => {
    #                                         'erlang_version' => '22.3',
    #                                         'rabbitmq_version' => '3.8.3'
    #                                     },
    #                 'rabbit@czcszjj3' => {
    #                                         'rabbitmq_version' => '3.8.3',
    #                                         'erlang_version' => '22.3'
    #                                     }
    #                 },
    # 'listeners' => {
    #                 'rabbit@czcszjj2' => [
    #                                         {
    #                                             'purpose' => 'inter-node and CLI tool communication',
    #                                             'interface' => '[::]',
    #                                             'node' => 'rabbit@czcszjj2',
    #                                             'protocol' => 'clustering',
    #                                             'port' => 25672
    #                                         },
    #                                         {
    #                                             'port' => 5672,
    #                                             'protocol' => 'amqp',
    #                                             'node' => 'rabbit@czcszjj2',
    #                                             'interface' => '[::]',
    #                                             'purpose' => 'AMQP 0-9-1 and AMQP 1.0'
    #                                         },
    #                                         {
    #                                             'purpose' => 'HTTP API',
    #                                             'protocol' => 'http',
    #                                             'port' => 15672,
    #                                             'node' => 'rabbit@czcszjj2',
    #                                             'interface' => '[::]'
    #                                         }
    #                                         ],
    #                 'rabbit@czcszjj1' => [
    #                                         {
    #                                             'interface' => '[::]',
    #                                             'node' => 'rabbit@czcszjj1',
    #                                             'protocol' => 'clustering',
    #                                             'port' => 25672,
    #                                             'purpose' => 'inter-node and CLI tool communication'
    #                                         },
    #                                         {
    #                                             'purpose' => 'AMQP 0-9-1 and AMQP 1.0',
    #                                             'interface' => '[::]',
    #                                             'node' => 'rabbit@czcszjj1',
    #                                             'port' => 5672,
    #                                             'protocol' => 'amqp'
    #                                         },
    #                                         {
    #                                             'protocol' => 'http',
    #                                             'port' => 15672,
    #                                             'node' => 'rabbit@czcszjj1',
    #                                             'interface' => '[::]',
    #                                             'purpose' => 'HTTP API'
    #                                         }
    #                                         ],
    #                 'rabbit@czcszjj3' => [
    #                                         {
    #                                             'protocol' => 'clustering',
    #                                             'port' => 25672,
    #                                             'interface' => '[::]',
    #                                             'node' => 'rabbit@czcszjj3',
    #                                             'purpose' => 'inter-node and CLI tool communication'
    #                                         },
    #                                         {
    #                                             'purpose' => 'AMQP 0-9-1 and AMQP 1.0',
    #                                             'port' => 5672,
    #                                             'protocol' => 'amqp',
    #                                             'interface' => '[::]',
    #                                             'node' => 'rabbit@czcszjj3'
    #                                         },
    #                                         {
    #                                             'purpose' => 'HTTP API',
    #                                             'port' => 15672,
    #                                             'protocol' => 'http',
    #                                             'node' => 'rabbit@czcszjj3',
    #                                             'interface' => '[::]'
    #                                         }
    #                                         ]
    #                 },
    # 'alarms' => [],
    # 'cluster_name' => 'rabbit@czcszjj3',
    # 'ram_nodes' => [
    #                 'rabbit@czcszjj2'
    #                 ],
    # 'partitions' => {},
    # 'disk_nodes' => [
    #                     'rabbit@czcszjj1',
    #                     'rabbit@czcszjj3'
    #                 ],
    # 'feature_flags' => [
    #                     {
    #                         'desc' => 'Count unroutable publishes to be dropped in stats',
    #                         'provided_by' => 'rabbitmq_management_agent',
    #                         'name' => 'drop_unroutable_metric',
    #                         'state' => 'disabled',
    #                         'stability' => 'stable',
    #                         'doc_url' => ''
    #                     },
    #                     {
    #                         'desc' => 'Count AMQP `basic.get` on empty queues in stats',
    #                         'provided_by' => 'rabbitmq_management_agent',
    #                         'name' => 'empty_basic_get_metric',
    #                         'state' => 'disabled',
    #                         'stability' => 'stable',
    #                         'doc_url' => ''
    #                     },
    #                     {
    #                         'doc_url' => '',
    #                         'stability' => 'stable',
    #                         'state' => 'enabled',
    #                         'name' => 'implicit_default_bindings',
    #                         'provided_by' => 'rabbit',
    #                         'desc' => 'Default bindings are now implicit, instead of being stored in the database'
    #                     },
    #                     {
    #                         'state' => 'enabled',
    #                         'doc_url' => 'https://www.rabbitmq.com/quorum-queues.html',
    #                         'stability' => 'stable',
    #                         'provided_by' => 'rabbit',
    #                         'desc' => 'Support queues of type `quorum`',
    #                         'name' => 'quorum_queue'
    #                     },
    #                     {
    #                         'state' => 'enabled',
    #                         'stability' => 'stable',
    #                         'doc_url' => '',
    #                         'desc' => 'Virtual host metadata (description, tags, etc)',
    #                         'provided_by' => 'rabbit',
    #                         'name' => 'virtual_host_metadata'
    #                     }
    #                     ],
    # 'running_nodes' => [
    #                     'rabbit@czcszjj2',
    #                     'rabbit@czcszjj3',
    #                     'rabbit@czcszjj1'
    #                     ]
    # };

    my $versionsMap = $clusterInfo->{versions};
    if(defined($versionsMap) and defined($versionsMap->{$myNodeName})){
        $appInfo->{ERLANG_VERSION} = $versionsMap->{$myNodeName}->{erlang_version};
    }
    
    #实例集群
    #my $connGather      = $self->{connGather};
    #my @memberIps       = $connGather->getInboundIps( ":$clusterPort", $mainPid );
    my @memberIps = ();
    foreach my $runningNode ( @{ $clusterInfo->{running_nodes} } ) {
        my $runningNode =~ s/.*?\@//;
        my $nodeIp = gethostbyname($runningNode);
        if ( defined($nodeIp) ) {
            push( @memberIps, $nodeIp );
        }
    }
    my @sortedMemberIps = sort(@memberIps);
    my $primaryIp       = $sortedMemberIps[0];
    my @memberPeer      = ();
    foreach my $memberIp (@sortedMemberIps) {
        push( @memberPeer, "$memberIp:$amqPort" );
    }

    my $clusterInfo = {
        _OBJ_CATEGORY => CollectObjCat->get('CLUSTER'),
        _OBJ_TYPE     => 'RabbitMQCluster',
        UNIQUE_NAME   => "RabbitMQ:$primaryIp:$amqPort",
        PRIMARY_IP    => $primaryIp,
        PORT          => $amqPort,
        CLUSTER_MODE  => 'distribute',
        MEMBER_PEER   => \@memberPeer
    };

    return ( $appInfo, $clusterInfo );
}

1;
