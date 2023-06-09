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

sub getUser {
    my ($self) = @_;

    my $mysql = $self->{mysql};
    my @users;
    my $rows = $mysql->query(
        sql     => q{select distinct user from mysql.user where user not in ('mysql.session','mysql.sys')},
        verbose => $self->{isVerbose}
    );

    # +------+
    # | user |
    # +------+
    # | root |
    my @users;
    foreach my $row (@$rows) {
        if ( $row->{user} ne '' ) {
            push( @users, $row->{user} );
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
        if ( $line =~ /\bmysqld\s+(.*?)$/s ) {
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
        if ( $dbName ne 'information_schema' and $dbName ne 'mysql' and $dbName ne 'performance_schema' ) {
            push( @dbNames, $dbName );
        }
    }

    #$mysqlInfo->{DATABASES} = \@dbNames;

    $rows = $mysql->query(
        sql     => q{select * from information_schema.schemata},
        verbose => $self->{isVerbose}
    );

    # +--------------+-------------------------+----------------------------+------------------------+----------+
    # | CATALOG_NAME | SCHEMA_NAME             | DEFAULT_CHARACTER_SET_NAME | DEFAULT_COLLATION_NAME | SQL_PATH |
    # +--------------+-------------------------+----------------------------+------------------------+----------+
    # | def          | ApolloConfigDB          | utf8                       | utf8_bin               | NULL     |
    # | def          | ApolloPortalDB          | utf8                       | utf8_bin               | NULL     |

    my $dbCharsetInfo = {};
    foreach my $row (@$rows) {
        my $dbInfo = {};
        $dbInfo->{_OBJ_CATEGORY}                = CollectObjCat->get('DB');
        $dbInfo->{_OBJ_TYPE}                    = 'Mysql-DB';
        $dbInfo->{NAME}                         = $row->{SCHEMA_NAME};
        $dbInfo->{DEFAULT_CHARACTER_SET}        = $row->{DEFAULT_CHARACTER_SET_NAME};
        $dbInfo->{DEFAULT_COLLATION}            = $row->{DEFAULT_COLLATION_NAME};
        $dbInfo->{PRIMARY_IP}                   = $bizIp;
        $dbInfo->{VIP}                          = $vip;
        $dbInfo->{PORT}                         = $port;
        $dbInfo->{SSL_PORT}                     = undef;
        $dbInfo->{SERVICE_ADDR}                 = "$vip:$port";
        $dbCharsetInfo->{ $row->{SCHEMA_NAME} } = $dbInfo;
        $dbInfo->{INSTANCES}                    = [
            {
                _OBJ_CATEGORY => CollectObjCat->get('DBINS'),
                _OBJ_TYPE     => 'Mysql',
                INSTANCE_NAME => $procInfo->{HOST_NAME},
                MGMT_IP       => $mysqlInfo->{MGMT_IP},
                PORT          => $port
            }
        ];
    }

    my @dbInfos = ();
    foreach my $dbName (@dbNames) {
        push( @dbInfos, $dbCharsetInfo->{$dbName} );
    }
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
        sql     => q{select substring_index(host,':',1) slave_host from information_schema.processlist where COMMAND='Binlog Dump'},
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
        $mysqlInfo->{'CLUSTER_MODE'} = undef;
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
