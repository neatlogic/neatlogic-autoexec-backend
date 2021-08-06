#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package SybaseCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps  => ['\bdataserver\b'],                       #正则表达是匹配ps输出
        psAttrs  => { PPID => '1', COMM => 'dataserver' },    #ps的属性的精确匹配
        envAttrs => { SYBROOT => undef, SYBASE => undef }     #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

#采集数据对象的Primary Key设置，只需要在返回多种类型对象的收集器里定义
#注意：！！如果是返回单类型对象的采集器不需要定义此函数，可以删除此函数
sub getPK {
    my ($self) = @_;
    return {
        #默认KEY用类名去掉Collector，对应APP_TYPE属性值
        #配置值就是作为PK的属性名
        $self->{defaultAppType} => [ 'MGMT_IP', 'PORT' ]

            #如果返回的是多种对象，需要手写APP_TYPE对应的PK配置
    };
}

sub isqlRun {
    my ( $self, $cmd, $user ) = @_;

    my $utils = $self->{collectUtils};

    my $execute;
    if ( $utils->{isRoot} ) {
        $execute = qq{su - $user -c 'isql -Usa -P -w 120' << EOF
            $cmd
            exit; 
            EOF
            };
    }
    else {
        $execute = qq{isql -Usa -P -w 120 << EOF
            $cmd
            exit; 
            EOF
            };
    }

    $execute =~ s/\n\+/\n/g;

    my $result = `$execute`;
    return $result;
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
#采集器实现需要重载这个类
#Return：如果判断当前进程不是想要的进程，返回undef，否则返回应用信息的HashMap
sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    my $user             = $procInfo->{USER};
    my $envMap           = $procInfo->{ENVIRONMENT};
    my $cmdLine          = $procInfo->{COMMAND};

    my @collectSet = ();
    my $objType    = $CollectObjType::DB;

    my $homePath = $envMap->{SYBASE};

    #sybase   30851 30850  7 23:23 ?        00:00:25 /home/sybase/ASE-15_0/bin/dataserver -d/home/sybase/data/master.dat -e/home/sybase/ASE-15_0/install/SITDEPLOY24.log -c/home/sybase/ASE-15_0/SITDEPLOY24.cfg -M/home/sybase/ASE-15_0 -sSITDEPLOY24
    my $binPath;
    if ( $cmdLine =~ /^\s*(.*\bdataserver)\s/ ) {
        $binPath = $1;
    }
    my $confFile;
    if ( $cmdLine =~ /\s-c\s{0,1}(\S+)/ ) {
        $confFile = $1;
    }
    my $dataFile;
    if ( $cmdLine =~ /\s-d\s{0,1}(\S+)/ ) {
        $dataFile = $1;
    }
    my $errorLog;
    if ( $cmdLine =~ /\s-e\s{0,1}(\S+)/ ) {
        $errorLog = $1;
    }
    my $serverName;
    if ( $cmdLine =~ /\s-s\s{0,1}(\S+)/ ) {
        $serverName = $1;
    }

    my $confPath = dirname($confFile);

    my $version;
    my $verInfo = $self->getCmdOut( "$binPath -v", $user );
    if ( $verInfo =~ /Adaptive Server Enterprise\/([\d\.]+)/ ) {
        $version = $1;
    }

    # SITDEPLOY24
    #         master tcp ether sit_deploy_24 5002
    #         master tcp ether 192.168.0.24 5002
    #         query tcp ether sit_deploy_24 5002
    #         query tcp ether 192.168.0.24 5002
    my $insInfo = $self->getFileContent("$homePath/interfaces");

    while ( $insInfo =~ /(\S+)\s*\n\s*master.*?(\S+)\s+(\d+)\s*\n/sg ) {
        my $insName = $1;
        my $ip      = $2;
        my $port    = $3;

        my $insInfo = {
            OBJECT_TYPE  => $objType,
            SERVER_NAME  => $insName,
            INSTALL_PATH => $homePath,
            CONF_PATH    => $confPath,
            ERROR_LOG    => $errorLog,
            DATA_FILE    => $dataFile,
            VERSION      => $version,
            PORT         => $port,
            SSL_PORT     => undef
        };
        if ( $ip =~ /\d+(\.\d+){3}/ ) {
            $insInfo->{IP} = $ip;
        }
        else {
            my $ipAddr = gethostbyname($ip);
            $insInfo->{IP} = inet_ntoa($ipAddr);
        }

        #get all dbs
        my $dbQuery = q{
                sp_helpdb
                go
            };
        my $dbNameInfo = isqlRun($dbQuery);
        my @dbNames    = $dbNameInfo =~ /\s(\S+)\s+\d+\.\d\sMB/sg;
        $insInfo->{DB_NAMES} = \@dbNames;

        #get all users
        my $userQuery = q {
                sp_helpuser
                go
            };
        my $userInfo = isqlRun($userQuery);
        my @users    = $userInfo =~ /\s(\w+)\s+\d+/sg;
        $insInfo->{USERS} = \@users;

        push( @collectSet, $insInfo );
    }

    return @collectSet;
}

1;
