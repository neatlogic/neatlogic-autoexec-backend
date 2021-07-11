#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package MysqlCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;
use MysqlExec;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps => ['\bmysqld\s'],         #正则表达是匹配ps输出
        psAttrs => { COMM => 'mysqld' }    #ps的属性的精确匹配
    };
}

#采集数据对象的Primary Key设置，只需要在返回多种类型对象的收集器里定义
#注意：！！如果是返回单类型对象的采集器不需要定义此函数，可以删除此函数
sub getPK {
    my ($self) = @_;
    return {
        #默认KEY用类名去掉Collector，对应APP_TYPE属性值
        #配置值就是作为PK的属性名
        $self->{defaultAppType} => [ 'MANAGE_IP', 'PORT', ]

            #如果返回的是多种对象，需要手写APP_TYPE对应的PK配置
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
    my ( $self, $command ) = @_;

    my $opts = {};
    my @items = split( /\s+--/, $command );
    $opts->{mysqldPath} = $items[0];
    if ( $items[0] =~ /^(.*?)\/bin\/mysqld/ ) {
        $opts->{mysqlHome} = $1;
    }

    for ( my $i = 1 ; $i < scalar(@items) ; $i++ ) {
        my $item = $items[$i];
        my ( $key, $val ) = split( '=', $item );
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
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $mysqlInfo = {};
    $mysqlInfo->{OBJECT_TYPE} = $CollectObjType::DB;

    #设置此采集到的对象对象类型，可以是：CollectObjType::APP，CollectObjType::DB，CollectObjType::OS

    my $osUser     = $procInfo->{USER};
    my $command    = $procInfo->{COMMAND};
    my $opts       = $self->parseCommandOpts($command);
    my $mysqlHome  = $opts->{mysqlHome};
    my $mysqldPath = $opts->{mysqldPath};

    $mysqlInfo->{INSTALL_PATH}  = $mysqlHome;
    $mysqlInfo->{CONFIG_FILE}   = $opts->{'defaults-file'};
    $mysqlInfo->{MYSQL_BASE}    = $opts->{'basedir'};
    $mysqlInfo->{MYSQL_DATADIR} = $opts->{'datadir'};
    $mysqlInfo->{ERROR_LOG}     = $opts->{'log-error'};
    $mysqlInfo->{SOCKET_PATH}   = $opts->{'socket'};

    my $port = $opts->{'port'};
    my $host = 127.0.0.1;

    if ( not defined($port) ) {
        my $listenAddrs = $procInfo->{CONN_INFO}->{LISTEN};
        if ( scalar(@$listenAddrs) > 1 ) {
            $port = $$listenAddrs[0];
            if ( $port =~ /^(.*?):(\d+)$/ ) {
                $host = $1;
                $port = $2;
            }
        }
    }

    $mysqlInfo->{PORT}           = $port;
    $mysqlInfo->{SSL_PORT}       = $port;
    $mysqlInfo->{MON_PORT}       = $port;
    $mysqlInfo->{ADMIN_PORT}     = $port;
    $mysqlInfo->{ADMIN_SSL_PORT} = $port;

    my $verOut = $self->getCmdOut( "'$mysqldPath' -version", $osUser );
    my $version;
    if ( $verOut =~ /\(mysqld\s+(.*?)\)/s ) {
        $version = $1;
    }
    $mysqlInfo->{VERSION} = $version;

    my $mysql = MysqlExec->new(
        mysqlHome => $mysqlHome,

        #username=>$username,
        #password=>$password,
        host => $host,
        port => $port
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
    $mysqlInfo->{DATABASES} = \@dbNames;

    #TODO：需要补充db的字符集等信息

    my $charSet;
    $rows = $mysql->query(
        sql     => q{show variables like 'character_set_system';},
        verbose => $self->{isVerbose}
    );

    # +----------------------+-------+
    # | Variable_name        | Value |
    # +----------------------+-------+
    # | character_set_system | utf8  |
    # +----------------------+-------+
    if ( salar(@$rows) > 0 ) {
        $charSet = $$rows[0]->{Value};
    }
    $mysqlInfo->{SYSTEM_CHARSET} = $charSet;

    #TODO: 集群相关的信息

    #服务名, 要根据实际来设置
    $mysqlInfo->{SERVER_NAME} = $procInfo->{APP_TYPE};

    return $mysqlInfo;

    #如果返回多个应用信息，则：return ($appInfo1, $appInfo2);
}

1;
