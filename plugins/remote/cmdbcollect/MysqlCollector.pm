#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package MysqlCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Socket;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use MysqlExec;

#权限需求：
#CONNECT权限
#SHOW DATABASES权限
#replication client权限
#mysql库只读
#information_schema库只读

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps => ['\bmysqld\b'],        #正则表达是匹配ps输出
        psAttrs => { COMM => 'mysqld' }
    };
}

sub init {
    my ($self) = @_;
    $self->{userGrantedDBMap} = {};
    $self->{dbGrantedUserMap} = {};
}

sub getUserGrants {
    my ( $self, $dbNames, $userName, $userAndhost ) = @_;

    my $userGrantedDBMap = $self->{userGrantedDBMap};
    my $user2DBsMap      = $userGrantedDBMap->{$userName};

    my $dbGrantedUserMap = $self->{dbGrantedUserMap};

    my @hostDetail    = split( ",", $userAndhost );
    my $grantedDBsMap = {};

    my $mysql = $self->{mysql};
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

    my $dbName2UsersMap = {};
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
            $db2UsersMap->{$userName}    = 1;
            $dbGrantedUserMap->{$dbName} = $db2UsersMap;
        }
    }

    my @userGrantedDBs = keys(%$user2DBsMap);
    return \@userGrantedDBs;
}

sub getUsers {
    my ( $self, $mysqlInfo, $dbNames ) = @_;

    my $mysql = $self->{mysql};
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
        if ( $row->{user} ne '' ) {
            my $hostsDef   = $row->{host};
            my @grantHosts = split( ',', $hostsDef );

            my $user = {
                _OBJ_CATEGORY => CollectObjCat->get('DBINS'),
                _OBJ_TYPE     => 'DB-USER',
                NAME          => $row->{user},
                HOSTS         => \@grantHosts,
                GRANTED_DBS   => $self->getUserGrants( $dbNames, $row->{user}, $hostsDef )
            };
            push( @users, $user );
        }
    }

    #TODO: How to get user default table space, 老的是有有问题的，没有迁移过来

    return \@users;
}

sub parseCommandOpts {
    my ( $self, $command, $procInfo ) = @_;

    my $opts       = {};
    my @items      = split( /[\s"]+--/, $command );
    my $mysqldPath = $items[0];
    $mysqldPath =~ s/^\s*|\s*$//g;
    $mysqldPath =~ s/^"|"$//g;

    #$mysqldPath =~ s/\\/\//g;

    if ( not -e $mysqldPath and not -e "$mysqldPath.exe" ) {
        my $exeFile = $procInfo->{EXECUTABLE_FILE};
        if ( defined($exeFile) ) {
            $mysqldPath = $exeFile;
        }
        else {
            my $pid   = $procInfo->{PID};
            my $utils = $self->{collectUtils};
            $mysqldPath = $utils->getExecutablePath($pid);
        }
    }

    $mysqldPath =~ s/\\/\//g;
    $opts->{mysqldPath} = $mysqldPath;
    if ( $mysqldPath =~ /^(.*?)[\/\\]bin[\/\\]mysqld/ or $mysqldPath =~ /^(.*?)[\/\\]sbin[\/\\]mysqld/ ) {
        $opts->{mysqlHome} = $1;
    }

    for ( my $i = 1 ; $i < scalar(@items) ; $i++ ) {
        my $item = $items[$i];
        my ( $key, $val ) = split( '=', $item );
        $opts->{$key} = $val;
    }

    if ( not defined( $opts->{mysqlHome} ) ) {
        $opts->{mysqlHome} = $opts->{basedir};
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

    my $mysqlInfo = {};
    $mysqlInfo->{MGMT_IP}       = $procInfo->{MGMT_IP};
    $mysqlInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');

    #设置此采集到的对象对象类型，可以是：CollectObjCat->get('INS')，CollectObjCat->get('DBINS')，CollectObjCat::OS

    my $osType     = $procInfo->{OS_TYPE};
    my $osUser     = $procInfo->{USER};
    my $command    = $procInfo->{COMMAND};
    my $opts       = $self->parseCommandOpts( $command, $procInfo );
    my $mysqlHome  = $opts->{mysqlHome};
    my $mysqldPath = $opts->{mysqldPath};

    if ( not -e $mysqldPath and not -e "$mysqldPath.exe" ) {
        print("ERROR: Mysql bin $mysqldPath not found.\n");
        return undef;
    }

    $mysqlInfo->{INSTALL_PATH}  = $mysqlHome;
    $mysqlInfo->{MYSQL_BASE}    = $opts->{'basedir'};
    $mysqlInfo->{MYSQL_DATADIR} = $opts->{'datadir'};
    $mysqlInfo->{ERROR_LOG}     = $opts->{'log-error'};
    $mysqlInfo->{SOCKET_PATH}   = $opts->{'socket'};

    if ( $opts->{'defaults-file'} ) {
        $mysqlInfo->{CONFIG_FILE} = $opts->{'defaults-file'};
    }
    else {
        $mysqlInfo->{CONFIG_FILE} = '/etc/my.cnf';
    }

    my ( $ports, $port ) = $self->getPortFromProcInfo($mysqlInfo);
    if ( defined( $opts->{'port'} ) and $opts->{'port'} ne '' ) {
        $port = int( $opts->{'port'} );
    }

    if ( $port == 65535 or $port == 0 ) {
        print("WARN: Can not determine Mysql listen port.\n");
        return undef;
    }

    my $pFinder = $self->{pFinder};
    my ( $bizIp, $vip ) = $pFinder->predictBizIp( $connInfo, $port );
    #predictBizIp对Linux做了修正，secondary IP优先作为vip
    #上面获取vip的结果不对
    # my $vip = $mysqlInfo->{MGMT_IP};
    # if ( -e '/etc/keepalived/keepalived.conf' ) {
    #     my $keepaliveLines = $self->getFileLines('/etc/keepalived/keepalived.conf');
    #     foreach my $line (@$keepaliveLines) {
    #         if ( $line =~ /(\d+\.\d+\.\d+\.\d+)\//i ) {
    #             $vip = $1;
    #             last;
    #         }
    #     }
    # }

    $mysqlInfo->{PRIMARY_IP}     = $bizIp;
    $mysqlInfo->{VIP}            = $vip;
    $mysqlInfo->{PORT}           = $port;
    $mysqlInfo->{SERVICE_ADDR}   = "$vip:$port";
    $mysqlInfo->{SSL_PORT}       = undef;
    $mysqlInfo->{ADMIN_PORT}     = $port;
    $mysqlInfo->{ADMIN_SSL_PORT} = undef;

    my ( $helpRet, $verOutLines ) = $self->getCmdOutLines( qq{"$mysqldPath" --help}, $osUser );
    if ( $helpRet ne 0 ) {
        $verOutLines = $self->getCmdOutLines(qq{"$mysqldPath" --help});
    }
    my $version;
    foreach my $line (@$verOutLines) {
        if ( $line =~ /\bmysqld\s+Ver\s+(\S+)/s ) {
            $version = $1;
            last;
        }
    }
    $mysqlInfo->{VERSION} = $version;
    if ( $version =~ /(\d+)/ ) {
        $mysqlInfo->{MAJOR_VERSION} = "MySQL$1";
    }

    my $host  = '127.0.0.1';
    my $mysql = MysqlExec->new(
        mysqlHome => $mysqlHome,
        username  => $self->{defaultUsername},
        password  => $self->{defaultPassword},
        host      => $host,
        port      => $port
    );
    $self->{mysql} = $mysql;

    my $rows;
    $rows = $mysql->query(
        sql     => 'show databases;',
        verbose => $self->{isVerbose}
    );

    # +-------------------------+
    # | Database                |
    # +-------------------------+
    # | ApolloConfigDB          |
    # | asmv3                   |
    my @dbNames = ();
    foreach my $row (@$rows) {
        my $dbName = $row->{Database};
        if ( $dbName ne 'information_schema' and $dbName ne 'mysql' and $dbName ne 'performance_schema' and $dbName ne 'sys' ) {
            push( @dbNames, $dbName );
        }
    }

    #获取实例用户及访问权限
    $mysqlInfo->{USERS} = $self->getUsers( $mysqlInfo, \@dbNames );

    $rows = $mysql->query(
        sql     => q{select * from information_schema.schemata},
        verbose => $self->{isVerbose}
    );

    # +--------------+-------------------------+----------------------------+------------------------+----------+
    # | CATALOG_NAME | SCHEMA_NAME             | DEFAULT_CHARACTER_SET_NAME | DEFAULT_COLLATION_NAME | SQL_PATH |
    # +--------------+-------------------------+----------------------------+------------------------+----------+
    # | def          | ApolloConfigDB          | utf8                       | utf8_bin               | NULL     |
    # | def          | ApolloPortalDB          | utf8                       | utf8_bin               | NULL     |

    my $db2UsersMap = $self->{dbGrantedUserMap};
    my $dbInfosMap  = {};
    foreach my $row (@$rows) {
        my $dbInfo = {};
        my $dbName = $row->{SCHEMA_NAME};
        if ( $dbName ne 'information_schema' and $dbName ne 'mysql' and $dbName ne 'performance_schema' and $dbName ne 'sys' ) {
            $dbInfo->{_OBJ_CATEGORY}         = CollectObjCat->get('DB');
            $dbInfo->{_OBJ_TYPE}             = 'Mysql-DB';
            $dbInfo->{_APP_TYPE}             = 'Mysql';
            $dbInfo->{NAME}                  = $dbName;
            $dbInfo->{DB_NAME}               = $dbName;
            $dbInfo->{SERVICE_NAME}          = $dbName;
            $dbInfo->{DEFAULT_CHARACTER_SET} = $row->{DEFAULT_CHARACTER_SET_NAME};
            $dbInfo->{DEFAULT_COLLATION}     = $row->{DEFAULT_COLLATION_NAME};
            $dbInfo->{PRIMARY_IP}            = $bizIp;
            $dbInfo->{VERSION}               = $mysqlInfo->{'VERSION'};
            $dbInfo->{MAJOR_VERSION}         = $mysqlInfo->{'MAJOR_VERSION'};
            $dbInfo->{VIP}                   = $vip;
            $dbInfo->{PORT}                  = $port;
            $dbInfo->{SSL_PORT}              = undef;
            $dbInfo->{SERVICE_ADDR}          = "$vip:$port";
            $dbInfo->{INSTANCES}             = [
                {
                    _OBJ_CATEGORY => CollectObjCat->get('DBINS'),
                    _OBJ_TYPE     => 'Mysql',
                    INSTANCE_NAME => $procInfo->{HOST_NAME},
                    MGMT_IP       => $mysqlInfo->{MGMT_IP},
                    PORT          => $port
                }
            ];

            my @dbUserInfos = ();
            my @dbConns     = ();
            my $dbUsers     = $db2UsersMap->{$dbName};
            my @dbUserNames = keys(%$dbUsers);
            foreach my $dbUser (@dbUserNames) {
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

            $dbInfo->{USERS}       = \@dbUserInfos;
            $dbInfo->{CONNECTIONS} = \@dbConns;

            $dbInfosMap->{$dbName} = $dbInfo;
        }
    }

    my @dbInfos = values(%$dbInfosMap);
    $mysqlInfo->{DATABASES} = \@dbInfos;

    #收集集群相关的信息
    $rows = $mysql->query(
        sql     => q{show slave status},
        verbose => $self->{isVerbose}
    );
    my $slaveIoRunning = 'No';
    if ( defined($rows) and scalar(@$rows) > 0 ) {
        $slaveIoRunning = $$rows[0]->{Slave_IO_Running};
    }

    #binlog dump is a thread on a master server for sending binary log contents to a slave server.
    #Slave端连接到Master执行binlog提送到Slave，host字段是Slave的hostname
    $rows = $mysql->query(
        sql     => q{select substring_index(host,':',1) slave_host from information_schema.processlist where COMMAND like 'Binlog Dump%'},
        verbose => $self->{isVerbose}
    );
    my @slaveIps   = ();
    my @slaveHosts = ();
    foreach my $row (@$rows) {
        my $slaveHost = $row->{slave_host};
        push( @slaveHosts, $slaveHost );
        my $ipAddr = gethostbyname($slaveHost);
        push( @slaveIps, inet_ntoa($ipAddr) );
    }
    $mysqlInfo->{SLAVE_IPS} = \@slaveIps;

    $mysqlInfo->{'IS_CLUSTER'} = 1;
    if ( $slaveIoRunning eq 'Yes' and scalar(@slaveHosts) != 0 ) {

        #如果运行这SlaveIo而且同时在推送binlog到Slave，则是双主模式，两个节点都是Master
        $mysqlInfo->{'CLUSTER_MODE'} = 'Master-Master';
        $mysqlInfo->{'CLUSTER_ROLE'} = 'Master';
    }
    elsif ( $slaveIoRunning eq 'Yes' and scalar(@slaveHosts) == 0 ) {

        #如果运行这SlaveIo而且没有推送binlog到Slave，则是主从模式，当前节点是Slave
        $mysqlInfo->{'CLUSTER_MODE'} = 'Master-Slave';
        $mysqlInfo->{'CLUSTER_ROLE'} = 'Slave';
    }
    elsif ( $slaveIoRunning ne 'Yes' and scalar(@slaveHosts) != 0 ) {

        #如果SlaveIo没有运行，而且推送binlog到Slave，则是主从模式，当前节点是Master
        $mysqlInfo->{'CLUSTER_MODE'} = 'Master-Slave';
        $mysqlInfo->{'CLUSTER_ROLE'} = 'Master';
    }
    else {
        #否则就是单节点运行
        $mysqlInfo->{'IS_CLUSTER'}   = 0;
        $mysqlInfo->{'CLUSTER_MODE'} = 'Single';
        $mysqlInfo->{'CLUSTER_ROLE'} = undef;
    }

    $rows = $mysql->query(
        sql     => 'show global variables;',
        verbose => $self->{isVerbose}
    );
    my $variables = {};
    foreach my $row (@$rows) {
        $variables->{ $row->{Variable_name} } = $row->{Value};
    }
    map { $mysqlInfo->{ uc($_) } = $variables->{$_} } ( keys(%$variables) );
    $mysqlInfo->{SYSTEM_CHARSET} = $variables->{character_set_database};

    #服务名, 要根据实际来设置
    $mysqlInfo->{SERVER_NAME}   = $procInfo->{HOST_NAME};
    $mysqlInfo->{INSTANCE_NAME} = $procInfo->{HOST_NAME};

    my @collectSet = ();
    push( @collectSet, $mysqlInfo );
    push( @collectSet, @{ $mysqlInfo->{DATABASES} } );
    return @collectSet;
}

1;
