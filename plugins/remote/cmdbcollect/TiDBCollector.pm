#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package TiDBCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Socket;
use utf8;
use JSON;
use File::Spec;
use File::Find;
use File::Basename;
use Cwd qw(realpath);
use IO::File;
use CollectObjCat;
use MysqlExec;

#权限需求：
#SHOW GRANTS权限
#mysql库只读
#information_schema库只读

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps => ['tidb-server'],            #正则表达是匹配ps输出
        psAttrs => { COMM => 'tidb-server' }
    };
}

sub init {
    my ($self) = @_;
    my $procInfo = $self->{procInfo};
    $self->{mgmtIp}           = $procInfo->{MGMT_IP};
    $self->{dbGrantedUserMap} = {};
    $self->{userGrantedDBMap} = {};
}

sub getVersion {
    my ( $self, $installPath ) = @_;

    my $version;
    my $outLines = $self->getCmdOutLines(qq{$installPath/bin/tidb-server -V});

    # Release Version: v5.1.4
    # Edition: Community
    # Git Commit Hash: 094b3e5e69d0921e2abe6907d217478bb5a7082d
    # Git Branch: heads/refs/tags/v5.1.4
    foreach my $line (@$outLines) {
        if ( $line =~ /Version:\s*(.*)\s*$/i ) {
            $version = $1;
            last;
        }
    }

    return $version;
}

sub getTiupUser {
    my ($self) = @_;
    my $tiUpUser;

    #find /root/.tiup -name tiup
    my @tiupFiles = ();
    File::Find::find(
        {
            wanted => sub {
                my $fileName    = $_;
                my $fileFullDir = $File::Find::name;
                if ( $fileName eq 'tiup' ) {
                    push( @tiupFiles, $fileFullDir );
                }
            },
            follow => 1
        },
        '/root/.tiup'
    );

    if (@tiupFiles) {
        $tiUpUser = 'root';
        foreach my $tiupFile (@tiupFiles) {
            my $fileUid = ( stat($tiupFile) )[4];
            $tiUpUser = ( getpwuid($fileUid) )[0];
            last;
        }
    }
    return $tiUpUser;
}

sub getClusterInfo {
    my ( $self, $tiupUser ) = @_;

    # Name                 User  Version  Path                                                      PrivateKey
    # ----                 ----  -------  ----                                                      ----------
    # tidb-dsg-dp-cluster  tidb  v5.1.4   /root/.tiup/storage/cluster/clusters/tidb-dsg-dp-cluster  /root/.tiup/storage/cluster/clusters/tidb-dsg-dp-cluster/ssh/id_rsa

    my ( $status, $outLines ) = $self->getCmdOutLines( qq{tiup cluster list}, $tiupUser );
    if ( $status ne 0 ) {
        $outLines = $self->getCmdOutLines(qq{tiup cluster list});
    }

    my $headerLine  = $$outLines[0];
    my $clusterLine = $$outLines[-1];

    my $clusterInfo  = {};
    my @headers      = split( /\s+/, $headerLine );
    my @clusterAttrs = split( /\s+/, $clusterLine );
    for ( my $i = 0 ; $i <= $#headers ; $i++ ) {
        $clusterInfo->{ $headers[$i] } = $clusterAttrs[$i];
    }

    return $clusterInfo;
}

sub getClusterComponentInfos {
    my ( $self, $tiupUser, $clusterName ) = @_;

    # Cluster type:       tidb
    # Cluster name:       tidb-dsg-dp-cluster
    # Cluster version:    v5.1.4
    # Deploy user:        tidb
    # SSH type:           builtin
    # Dashboard URL:      http://10.244.103.26:2379/dashboard
    # ID                   Role          Host           Ports        OS/Arch        Status  Data Dir                             Deploy Dir
    # --                   ----          ----           -----        -------        ------  --------                             ----------
    # 10.244.103.26:9093   alertmanager  10.244.103.26  9093/9094    linux/aarch64  Up      /tidb01/tidb-data/alertmanager-9093  /tidb01/tidb-deploy/alertmanager-9093
    # 10.244.103.26:3000   grafana       10.244.103.26  3000         linux/aarch64  Up      -                                    /tidb01/tidb-deploy/grafana-3000
    # 10.244.103.24:2379   pd            10.244.103.24  2379/2380    linux/aarch64  Up|L    /tidb01/tidb-data/pd-2379            /tidb01/tidb-deploy/pd-2379
    # Total nodes: 18
    my ( $status, $outLines ) = $self->getCmdOutLines( qq{tiup cluster display $clusterName}, $tiupUser );
    if ( $status ne 0 ) {
        $outLines = $self->getCmdOutLines(qq{tiup cluster display $clusterName});
    }

    my $lineCount = scalar(@$outLines);
    my $startIdx  = 0;
    for ( $startIdx = 0 ; $startIdx < $lineCount ; $startIdx++ ) {
        if ( $$outLines[$startIdx] =~ /^[-\s]+$/ ) {
            $startIdx = $startIdx - 1;
            last;
        }
    }
    my $headerLine = $$outLines[$startIdx];
    my $splitLine  = $$outLines[ $startIdx + 1 ];

    my @startPoses = ();
    while ( $splitLine =~ /-+/pg ) {
        my $matchEndPos = pos($splitLine);
        my $minusCount  = length( ${^MATCH} );
        push( @startPoses, $matchEndPos - $minusCount );
    }
    my @substrParams = ();
    for ( my $i = 0 ; $i < $#startPoses ; $i++ ) {
        push( @substrParams, [ $startPoses[$i], $startPoses[ $i + 1 ] - $startPoses[$i] ] );
    }
    my $uIntMax = ~0;
    push( @substrParams, [ $startPoses[-1], $uIntMax ] );

    my @headers = ();
    foreach my $position (@substrParams) {
        my $header = substr( $headerLine, $$position[0], $$position[1] );
        $header =~ s/^\s*|\s*$//g;
        push( @headers, $header );
    }

    my @components = ();
    for ( my $i = $startIdx + 2 ; $i < $lineCount - 1 ; $i++ ) {
        my $componentInfo = {};
        my $line          = $$outLines[$i];
        for ( my $k = 0 ; $k <= $#substrParams ; $k++ ) {
            my $param    = $substrParams[$k];
            my $fieldVal = substr( $line, $$param[0], $$param[1] );
            $fieldVal =~ s/^\s*|\s*$//g;
            $componentInfo->{ $headers[$k] } = $fieldVal;
        }
        push( @components, $componentInfo );
    }

    return \@components;
}

sub getPDServerInfo {
    my ( $self, $user, $pdAddrs ) = @_;

    my $pdInfo = {};

#tidb     1416620       1 12 Feb19 ?        3-19:15:41 bin/pd-server --name=pd-1 --client-urls=http://0.0.0.0:2379 --advertise-client-urls=http://10.244.103.24:2379 --peer-urls=http://0.0.0.0:2380 --advertise-peer-urls=http://10.244.103.24:2380 --data-dir=/tidb01/tidb-data/pd-2379 --initial-cluster=pd-1=http://10.244.103.24:2380,pd-2=http://10.244.103.25:2380,pd-3=http://10.244.103.26:2380 --config=conf/pd.toml --log-file=/tidb01/tidb-deploy/pd-2379/log/pd.log

    my $outLines = $self->getCmdOutLines(qq{ps -u $user -fww | grep pd-server});

    my $pdServerPsLine;
    foreach my $outLine (@$outLines) {
        foreach my $pdAddr (@$pdAddrs) {
            my ( $pdIp, $pdPort ) = split( ':', $outLine );
            if ( $outLine =~ $pdIp and $outLine =~ $pdPort ) {
                $pdServerPsLine = $outLine;
            }
        }
    }

    if ( not defined($pdServerPsLine) ) {
        return $pdInfo;
    }

    if ( $pdServerPsLine =~ /--data-dir=(.*?)\s+--/ or $pdServerPsLine =~ /--data-dir=(.*?)\s+$/ ) {
        $pdInfo->{DATA_DIR} = dirname($1);
    }
    if ( $pdServerPsLine =~ /--data-dir=(.*?)\s+--/ or $pdServerPsLine =~ /--data-dir=(.*?)\s+$/ ) {
        $pdInfo->{DATA_DIR} = dirname($1);
    }

    return $pdInfo;
}

sub getDatabases {
    my ( $self, $mysql, $ip, $port ) = @_;
    my $rows = $mysql->query(
        sql     => q{select SCHEMA_NAME,DEFAULT_CHARACTER_SET_NAME,DEFAULT_COLLATION_NAME from information_schema.SCHEMATA},
        verbose => $self->{isVerbose}
    );

    # +--------------------+----------------------------+------------------------+
    # | SCHEMA_NAME        | DEFAULT_CHARACTER_SET_NAME | DEFAULT_COLLATION_NAME |
    # +--------------------+----------------------------+------------------------+
    # | dp_test            | utf8mb4                    | utf8mb4_bin            |
    # | INFORMATION_SCHEMA | utf8mb4                    | utf8mb4_bin            |
    # | METRICS_SCHEMA     | utf8mb4                    | utf8mb4_bin            |
    # | mysql              | utf8mb4                    | utf8mb4_bin            |
    # | PERFORMANCE_SCHEMA | utf8mb4                    | utf8mb4_bin            |
    # | test               | utf8mb4                    | utf8mb4_bin            |
    # | tlxd               | utf8mb4                    | utf8mb4_bin            |
    # +--------------------+----------------------------+------------------------+

    my $mgmtIp    = $self->{mgmtIp};
    my @databases = ();
    my @dbNames   = ();

    my $dbObjCat = CollectObjCat->get('DB');
    foreach my $row (@$rows) {
        my $dbName     = $row->{SCHEMA_NAME};
        my $charset    = $row->{DEFAULT_CHARACTER_SET_NAME};
        my $collation  = $row->{DEFAULT_COLLATION_NAME};
        my $excludeMap = {
            'performance_schema' => 1,
            'information_schema' => 1,
            'mysql'              => 1,
            'metrics_schema'     => 1,
            'test'               => 1,
            'db_meta'            => 1
        };

        if ( not defined( $excludeMap->{ lc($dbName) } ) ) {
            my $tidbInfo = {
                _OBJ_CATEGORY => $dbObjCat,
                _OBJ_TYPE     => 'TiDB',
                _APP_TYPE     => 'TiDB',
                NAME          => $dbName,
                DB_NAME       => $dbName,
                MGMT_IP       => $ip,

                #TODO: VIP的计算存疑，需要确认
                VIP       => $ip,
                PORT      => $port,
                CHARSET   => $charset,
                COLLATION => $collation,
                USERS     => []
            };

            push( @dbNames,   $dbName );
            push( @databases, $tidbInfo );
        }
    }
    return ( \@dbNames, \@databases );
}

sub getUserGrants {
    my ( $self, $mysql, $dbNames, $userName, $userAndhost ) = @_;

    my $userGrantedDBMap = $self->{userGrantedDBMap};
    my $user2DBsMap      = $userGrantedDBMap->{$userName};

    my $dbGrantedUserMap = $self->{dbGrantedUserMap};

    my @hostDetail    = split( ",", $userAndhost );
    my $grantedDBsMap = {};

    foreach my $grantedHost (@hostDetail) {
        my $rows = $mysql->query(
            sql     => qq{show grants for $grantedHost},
            verbose => $self->{isVerbose}
        );

        #+-------------------------------------------------------------------------------------+
        #| Grants for dbsnmp@%                                                                 |
        #+-------------------------------------------------------------------------------------+
        #| GRANT SELECT, PROCESS, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'dbsnmp'@'%' |
        #+-------------------------------------------------------------------------------------+
        #mysql> show grants for nacos@'%';
        #+-----------------------------------------------------------------------------+
        #| Grants for nacos@%                                                          |
        #+-----------------------------------------------------------------------------+
        #| GRANT USAGE ON *.* TO 'nacos'@'%'                                           |
        #| GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON `nacosdb`.* TO 'nacos'@'%' |
        #+-----------------------------------------------------------------------------+
        foreach my $row (@$rows) {
            foreach my $key ( keys(%$row) ) {
                if ( $row->{$key} !~ /USAGE/ ) {
                    if ( $row->{$key} =~ /^GRANT\s+.+?\s+ON\s+(.+?)\..+\s+TO/ ) {
                        my $grantedDB = $1;
                        $grantedDB =~ s/^`|`$//g;
                        $grantedDBsMap->{$grantedDB} = 1;
                    }
                }
            }
        }
    }

    foreach my $grantedObj ( keys(%$grantedDBsMap) ) {
        my $grantedDBs = [];
        if ( $grantedObj eq '*' ) {
            $grantedDBs = $dbNames;
        }
        else {
            $grantedDBs = [$grantedObj];
        }

        foreach my $dbName (@$grantedDBs) {
            $user2DBsMap->{$dbName} = 1;
            my $db2UsersMap = $dbGrantedUserMap->{$dbName};
            $db2UsersMap->{$userName} = 1;
            $dbGrantedUserMap->{$dbName} = $db2UsersMap;
        }
    }

    my @userGrantedDBs = keys(%$user2DBsMap);
    return \@userGrantedDBs;
}

sub getUsers {
    my ( $self, $mysql, $dbNames ) = @_;

    my @users;
    my $rows = $mysql->query(

        #sql     => q{select distinct user from mysql.user where user not in ('mysql.session','mysql.sys')},
        sql     => q{select user,group_concat(concat(user,'@''',host,'''')) as host from mysql.user where user not in ('mysql.session','mysql.sys') group by user},
        verbose => $self->{isVerbose}
    );

    # +--------+------------------------------------------------------+
    # | user   | host                                                 |
    # +--------+------------------------------------------------------+
    # | dbsnmp | dbsnmp@'%',dbsnmp@'localhost',dbsnmp@'127.0.0.1'     |
    # | nacos  | nacos@'10.4.48.11',nacos@'%',nacos@'10.4.48.12'      |
    # | repl   | repl@'%'                                             |
    # | root   | root@'localhost',root@'10.4.48.11',root@'10.4.48.12' |
    # +--------+------------------------------------------------------+
    my @users;
    foreach my $row (@$rows) {
        my $userName   = $row->{user};
        if ( $userName ne '' ) {
            my $hostsDef   = $row->{host};
            my @grantHosts = split( ',', $hostsDef );

            my $user = {
                _OBJ_CATEGORY => CollectObjCat->get('DBINS'),
                _OBJ_TYPE     => 'DB-USER',
                NAME          => $userName,
                HOSTS         => \@grantHosts,
                GRANTED_DBS   => $self->getUserGrants( $mysql, $dbNames, $userName, $hostsDef )
            };
            push( @users, $user );
        }
    }

    #TODO: How to get user default table space, 老的是有有问题的，没有迁移过来

    return \@users;
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
sub collect {
    my ($self) = @_;

    my @collectSet = ();
    $self->{isVerbose} = 1;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};

    my $osType           = $procInfo->{OS_TYPE};
    my $pFinder          = $self->{pFinder};
    my $connInfo         = $procInfo->{CONN_INFO};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $osUser  = $procInfo->{USER};
    my $mgmtIp  = $self->{mgmtIp};
    my $cmdLine = $procInfo->{COMMAND};

    my $portInfoMap = $connInfo->{PORT_BIND};

    #获取tiup用户
    my $tiupUser = $self->getTiupUser();

    #没有tiup用户就不采集
    # if ( not defined($tiupUser) ) {
    #     print("WARN: There is no TiDB cluster.\n");
    #     return undef;
    # }
    print("INFO: TiDB tiup run on user $tiupUser\n");

    my $clusterName;
    my $dbInsObjCat    = CollectObjCat->get('DBINS');
    my @dbInses        = ();
    my @tiDBComponents = ();
    my @dbInsAddrs     = ();
    my @pdAddrs        = ();

    my $tidbInfo = {
        _OBJ_CATEGORY => $dbInsObjCat,
        _OBJ_TYPE     => 'TiDB',
        _APP_TYPE     => 'TiDB'
    };

    my $exeFile     = $procInfo->{EXECUTABLE_FILE};
    my $binPath     = dirname($exeFile);
    my $installPath = dirname($binPath);

    my ( $ports, $port ) = $self->getPortFromProcInfo($tidbInfo);
    if ( $cmdLine =~ /-P\s*(\d+)/ ) {
        $port = $1;
    }
    my $portInfo     = $portInfoMap->{"$port"};
    my $portLsnIpMap = $pFinder->getPortListenIps( $connInfo, $port );

    my $logPath;
    if ( $cmdLine =~ /--log-file=(.*?)\s+--/ or $cmdLine =~ /--log-file=(.*?)\s+$/ ) {
        my $logFile = dirname($1);
        my $logPath = dirname($logFile);
    }
    if ( $cmdLine =~ /--config=(.*?)\s+--/ or $cmdLine =~ /--config=(.*?)\s+$/ ) {
        my $confFile = $1;
        if ( $confFile !~ /^[\\\/]/ ) {
            my $exeFileName = $procInfo->{COMM};
            if ( $cmdLine =~ /^(.*?$exeFileName)/ ) {
                my $relativePath = $1;
                my $workingPath  = substr( $exeFile, 0, length($exeFile) - length($relativePath) );
                $confFile = "$workingPath/$confFile";
            }
            $confFile = realpath($confFile);
        }
        $tidbInfo->{CONFIG_FILE} = $confFile;
    }

    my $version = $self->getVersion($installPath);
    my $pdInfo  = $self->getPDServerInfo( $osUser, \@pdAddrs );
    $tidbInfo->{VERSION} = $version;
    $tidbInfo->{PORT}    = $port;

    #$tidbInfo->{SERVICE_PORTS} = $ports;
    $tidbInfo->{DATA_DIR}     = $pdInfo->{DATA_DIR};
    $tidbInfo->{INSTALL_PATH} = $installPath;
    $tidbInfo->{BIN_PATH}     = $binPath;

    my $myInsIp;
    if ( $cmdLine =~ /--path=(\S+)/ ) {
        foreach my $pdAddr ( split( ',', $1 ) ) {
            push( @pdAddrs, $pdAddr );
            my ( $insIp, $pdPort ) = split( ':', $pdAddr );
            if ( defined( $portLsnIpMap->{$insIp} ) ) {
                $myInsIp = $insIp;
            }

            if ( not defined($tiupUser) or $tiupUser eq '' ) {
                my $dbAddr = "$insIp:$port";
                push( @dbInsAddrs, $dbAddr );
                push(
                    @dbInses,
                    {
                        _OBJ_CATEGORY => $dbInsObjCat,
                        _OBJ_TYPE     => 'TiDB',
                        _APP_TYPE     => 'TiDB',
                        INSTANCE_NAME => $dbAddr,
                        NODE_NAME     => $dbAddr,
                        MGMT_IP       => $insIp,
                        PORT          => $port
                    }
                );
            }
        }
    }
    $tidbInfo->{MGMT_IP}       = $myInsIp;
    $tidbInfo->{INSTANCE_NAME} = "$myInsIp:$port";

    if ( defined($tiupUser) and $tiupUser ne '' ) {

        #获取集群
        my $clusterInfo = $self->getClusterInfo($tiupUser);
        $clusterName = $clusterInfo->{Name};
        my $tidbUser = $clusterInfo->{User};
        $version = $clusterInfo->{Version};

        #获取集群组件信息
        my $componentList = $self->getClusterComponentInfos( $tiupUser, $clusterName );
        foreach my $component (@$componentList) {
            my ( $componentIp, $componentPort ) = split( ':', $component->{ID} );
            my ( $os, $arch )                   = split( '/', $component->{'OS/Arch'} );
            my $id   = $component->{ID};
            my $role = $component->{Role};

            my @ports = split( '/', $component->{Ports} );
            if ( $component->{Role} eq 'tidb' ) {
                push(
                    @dbInses,
                    {
                        _OBJ_CATEGORY => $dbInsObjCat,
                        _OBJ_TYPE     => 'TiDB',
                        _APP_TYPE     => 'TiDB',
                        INSTANCE_NAME => $id,
                        NODE_NAME     => $id,
                        MGMT_IP       => $componentIp,
                        PORT          => $componentPort

                            # PORTS         => \@ports,
                            # ID            => $component->{ID},
                            # ROLE          => $component->{Role},
                            # ARCH          => $arch,
                            # STATUS        => $component->{Status},
                            # DATA_DIR      => $component->{'Data Dir'},
                            # DEPLOY_DIR    => $component->{'Deploy Dir'},
                            # VERSION       => $version
                    }
                );
                push( @dbInsAddrs, $component->{ID} );
            }

            push(
                @tiDBComponents,
                {
                    _OBJ_CATEGORY => $dbInsObjCat,
                    _OBJ_TYPE     => 'TiDBComponent',
                    _APP_TYPE     => 'TiDB-' . $role,
                    NAME          => "$id/$role",
                    ID            => $id,
                    MGMT_IP       => $componentIp,
                    IP            => $componentIp,
                    PORT          => $componentPort,
                    PORTS         => \@ports,
                    ROLE          => $role,
                    ARCH          => $arch,
                    STATUS        => $component->{Status},
                    DATA_DIR      => $component->{'Data Dir'},
                    DEPLOY_DIR    => $component->{'Deploy Dir'},
                    VERSION       => $version,
                    RUN_ON        => {
                        _OBJ_CATEGORY => 'OS',
                        _OBJ_TYPE     => $osType,
                        MGMT_IP       => $componentIp
                    }
                }
            );
        }
    }

    my @sortedDBInsAddrs = sort(@dbInsAddrs);
    my ( $primaryComponentIp, $primaryComponentPort ) = split( ':', $sortedDBInsAddrs[0] );
    my $mysql = MysqlExec->new(
        mysqlHome => undef,
        username  => $self->{defaultUsername},
        password  => $self->{defaultPassword},
        host      => '127.0.0.1',
        port      => $primaryComponentPort
    );

    my ( $dbNames, $databases ) = $self->getDatabases( $mysql, $primaryComponentIp, $primaryComponentPort );
    $tidbInfo->{USERS} = $self->getUsers( $mysql, $dbNames );

    my $dbUsersMap = $self->{dbGrantedUserMap};

    foreach my $db (@$databases) {
        my $dbname  = $db->{'NAME'};
        my $dbUsers = $dbUsersMap->{$dbname};
        my @dbUserNames = keys(%$dbUsers);
        my @dbUserList = ();
        foreach my $dbUserName ( @dbUserNames ) {
                my $user = {};
                $user->{_OBJ_CATEGORY}  = CollectObjCat->get('DB');
                $user->{_OBJ_TYPE}      = 'DB-USER';
                $user->{NAME}           = $dbUserName;

                push( @dbUserList,$user );
        }

        $db->{USERS}     = \@dbUserList;
        $db->{INSTANCES} = \@dbInses;

        #数据库连接
        my @dbConns = ();
        foreach my $dbUser (@dbUserList) {
             my $dbConnect = {};
             $dbConnect->{_OBJ_CATEGORY} = CollectObjCat->get('DB');
             $dbConnect->{_OBJ_TYPE}     = 'DB-CONNECT';
             $dbConnect->{SERVICE_NAME}   = $dbname;
             $dbConnect->{USER_NAME}      = $dbUser->{NAME};
             push( @dbConns, $dbConnect );
        }
        $db->{'CONNECTIONS'} = \@dbConns;
    }

    push( @collectSet, $tidbInfo );

    if ( defined($tiupUser) ) {
        my $tidbClusterInfo = {
            _OBJ_CATEGORY => CollectObjCat->get('CLUSTER'),
            _OBJ_TYPE     => 'TiDBCluster',
            UNIQUE_NAME   => "TiDB:$primaryComponentIp:$primaryComponentPort",
            NAME          => $clusterName,
            VERSION       => $version,
            TIUP_IP       => $mgmtIp,
            PRIMARY_IP    => $primaryComponentIp,
            PORT          => $primaryComponentPort,
            CLUSTER_MODE  => 'distribute',
            MEMBER_PEER   => \@sortedDBInsAddrs,
            COMPONENTS    => \@tiDBComponents,
            DATABASES     => \@$databases
        };
        push( @collectSet, $tidbClusterInfo );
    }

    push( @collectSet, @$databases );
    return @collectSet;
}

1;
