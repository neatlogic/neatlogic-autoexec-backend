#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package DaMengCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);
use Socket;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use DisqlExec;

use JSON qw(to_json);

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps => ['\bdmserver\b'],        #正则表达是匹配ps输出
        psAttrs => { COMM => 'dmserver' }
    };
}

sub getInsVersion {
    my ($self) = @_;

    my $version = '';
    my $disql   = $self->{disql};

    my $sql = q{select REPLACE(banner, chr(10), ' ') VERSION from v$version where rownum <=1;};

    my $rows = $disql->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( defined($rows) and scalar(@$rows) > 0 ) {
        $version = $$rows[0]->{VERSION};
    }

    return $version;
}

sub getInsVersionByBinScriptFile {
    my ( $self, $dmHome ) = @_;

    my $verOutLines = $self->getCmdOutLines(qq{grep 'version:' $dmHome/bin/DmServiceDMSERVER});
    my $version;
    foreach my $line (@$verOutLines) {
        if ( $line =~ /\s*version:\s*(.*?)\s*$/ ) {
            $version = $1;
            last;
        }
    }
    return $version;
}

sub parseCommandOpts {
    my ( $self, $command, $procInfo ) = @_;

    my $opts = {};
    $command =~ s/-noconsole//g;
    my $dmserverPath = $command;
    if ( $command =~ /^\s*(.*?)\s+\w+=/ ) {
        $dmserverPath = $1;
    }
    $dmserverPath =~ s/^\s*|\s*$//g;
    $dmserverPath =~ s/^"|"$//g;

    #$dmserverPath =~ s/\\/\//g;

    if ( not -e $dmserverPath and not -e "$dmserverPath.exe" ) {
        my $exeFile = $procInfo->{EXECUTABLE_FILE};
        if ( defined($exeFile) ) {
            $dmserverPath = $exeFile;
        }
        else {
            my $pid   = $procInfo->{PID};
            my $utils = $self->{collectUtils};
            $dmserverPath = $utils->getExecutablePath($pid);
        }
    }

    $dmserverPath =~ s/\\/\//g;
    $opts->{dmserverPath} = $dmserverPath;
    if ( $dmserverPath =~ /^(.*?)[\/\\]bin[\/\\]dmserver/ or $dmserverPath =~ /^(.*?)[\/\\]sbin[\/\\]dmserver/ ) {
        $opts->{dmHome} = $1;
    }

    while ( $command =~ /(\w+)=(.*?)(?=\w+=)/ ) {
        my $key = $1;
        my $val = $2;
        $opts->{$key} = $val;
    }

    return $opts;
}

sub getIdCode {
    my ($self) = @_;

    my $idCode = '';
    my $disql  = $self->{disql};

    my $sql = q{select id_code() IDCODE;};

    my $rows = $disql->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( defined($rows) and scalar(@$rows) > 0 ) {
        $idCode = $$rows[0]->{IDCODE};
    }

    return $idCode;
}

sub getInstName {
    my ($self) = @_;

    my $instName = '';
    my $disql    = $self->{disql};

    my $sql = q{select NAME from v$instance;};

    my $rows = $disql->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( defined($rows) and scalar(@$rows) > 0 ) {
        $instName = $$rows[0]->{NAME};
    }

    return $instName;
}

sub getExpiredDate {
    my ( $self, $insInfo ) = @_;

    my $expiredDate = '';
    my $disql       = $self->{disql};

    my $sql = q{select EXPIRED_DATE from  v$license;};

    my $rows = $disql->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( defined($rows) and scalar(@$rows) > 0 ) {
        $expiredDate = $$rows[0]->{EXPIRED_DATE};
    }

    return $expiredDate;
}

sub getUserInfo {
    my ($self) = @_;

    my $disql = $self->{disql};
    my $sql   = q{select du.USERNAME,du.DEFAULT_TABLESPACE from dba_users du where du.account_status='OPEN' and du.default_tablespace not in('SYSTEM','SYSAUX')};

    my @userInfos = ();
    my $rows      = $disql->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( defined($rows) ) {
        foreach my $row (@$rows) {
            if ( defined $row->{USERNAME} and $row->{USERNAME} ne '' ) {
                push(
                    @userInfos,
                    {
                        _OBJ_CATEGORY      => CollectObjCat->get("DB"),
                        _OBJ_TYPE          => 'DB-USER',
                        NAME               => $row->{USERNAME},
                        DEFAULT_TABLESPACE => $row->{DEFAULT_TABLESPACE}
                    }
                );
            }
        }
    }

    return \@userInfos;
}

sub getTableSpaceInfo {
    my ($self) = @_;

    my $disql = $self->{disql};

    my $tableSpaces = {};

    my $sql = q{
        SELECT df.tablespace_name                    NAME,
            totalusedspace                        USED_MB,
            ( df.totalspace - tu.totalusedspace ) FREE_MB,
            df.totalspace                         TOTAL_MB,
            Round(100 * ( tu.totalusedspace / df.totalspace )) USED_PCT
        FROM   (SELECT tablespace_name,
                    Round(SUM(bytes) / ( 1024 * 1024 )) TotalSpace
                FROM   dba_data_files
                GROUP  BY tablespace_name) df,
            (SELECT Round(SUM(bytes) / ( 1024 * 1024 )) totalusedspace,
                    tablespace_name
                FROM   dba_segments
                GROUP  BY tablespace_name) tu
        WHERE  df.tablespace_name = tu.tablespace_name
    };
    $sql =~ s/\s+/ /g;

    my $rows = $disql->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( defined($rows) ) {
        foreach my $row (@$rows) {
            my $tableSpaceName = $row->{NAME};

            my $tableSpaceInfo = {};
            $tableSpaceInfo->{NAME}       = $tableSpaceName;
            $tableSpaceInfo->{TOTAL}      = int( $row->{TOTAL_MB} * 1000 / 1024 + 0.5 ) / 1000;
            $tableSpaceInfo->{USED}       = int( $row->{USED_MB} * 1000 / 1024 + 0.5 ) / 1000;
            $tableSpaceInfo->{FREE}       = int( $row->{FREE_MB} * 1000 / 1024 + 0.5 ) / 1000;
            $tableSpaceInfo->{USED_PCT}   = $row->{USED_PCT} + 0.0;
            $tableSpaceInfo->{DATA_FILES} = [];

            $tableSpaces->{$tableSpaceName} = $tableSpaceInfo;
        }
    }

    $sql = q{select tablespace_name TPN, file_name FN, round(bytes/1024/1024/1024, 3) G, autoextensible AEX from dba_data_files};

    $rows = $disql->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( defined($rows) ) {
        foreach my $row (@$rows) {
            my $dataFileInfo   = {};
            my $tableSpaceName = $row->{TPN};

            $dataFileInfo->{FILE_NAME} = $row->{FN};
            $dataFileInfo->{SIZE}      = $row->{G} + 0.0;
            my $isAutoExtended = $row->{AEX};
            $dataFileInfo->{AUTOEXTENSIBLE} = $isAutoExtended;

            my $tableSpace = $tableSpaces->{$tableSpaceName};

            #if ( not defined($tableSpace) ) {
            #    $tableSpace                     = { NAME => $tableSpaceName, DATA_FILES => [] };
            #    $tableSpaces->{$tableSpaceName} = $tableSpace;
            #    $tableSpace->{AUTOEXTENSIBLE}   = 'NO';
            #}
            if ( $isAutoExtended eq 'YES' ) {
                $tableSpace->{AUTOEXTENSIBLE} = 'YES';
            }

            my $dataFiles = $tableSpace->{DATA_FILES};
            push( @$dataFiles, $dataFileInfo );
        }
    }

    my @allTableSpaces = values(%$tableSpaces);
    return \@allTableSpaces;
}

sub getDataBases {
    my ( $self, $disql, $dmInfo ) = @_;

    my $bizIp = $dmInfo->{PRIMARY_IP};
    my $vip   = $dmInfo->{VIP};
    my $port  = $dmInfo->{PORT};

    #获取DB库
    my $rows;
    $rows = $disql->query(
        sql     => 'select NAME from v$instance;',
        verbose => $self->{isVerbose}
    );

    my $dbUsers = $dmInfo->{USERS};
    my @dbNames = ();
    foreach my $row (@$rows) {
        my $dbName = $row->{NAME};
        if ( defined $dbName and $dbName ne '' ) {
            my @dbCons = ();
            foreach my $user (@$dbUsers) {
                push(
                    @dbCons,
                    {
                        _OBJ_CATEGORY => CollectObjCat->get('DB'),
                        _OBJ_TYPE     => 'DB-CONNECT',
                        USER_NAME     => $user->{NAME},
                        SERVICE_NAME  => $dbName
                    }
                );
            }
            push(
                @dbNames,
                {
                    _OBJ_CATEGORY => CollectObjCat->get('DB'),
                    _OBJ_TYPE     => 'DaMeng-DB',
                    _APP_TYPE     => 'DaMeng',
                    NAME          => $dbName,
                    PRIMARY_IP    => $bizIp,
                    VIP           => $vip,
                    PORT          => $port,
                    SSL_PORT      => undef,
                    SERVICE_ADDR  => "$vip:$port",
                    CONNCTIONS    => \@dbCons,
                    INSTANCES     => [
                        {
                            _OBJ_CATEGORY => CollectObjCat->get('DBINS'),
                            _OBJ_TYPE     => 'DaMeng',
                            INSTANCE_NAME => $dmInfo->{INSTANCE_NAME},
                            MGMT_IP       => $dmInfo->{MGMT_IP},
                            PORT          => $dmInfo->{PORT}
                        }
                    ],
                    USERS => $dbUsers
                }
            );
        }
    }
    $dmInfo->{DATABASES} = \@dbNames;

    return;
}

sub getParameters {
    my ( $self, $disql, $dmInfo ) = @_;

    #获取参数
    my $rows = $disql->query(
        sql     => q{select para_name,para_value from v$dm_ini;},
        verbose => $self->{isVerbose}
    );

    my $results;
    foreach my $row (@$rows) {
        $results->{ $row->{para_name} } = $row->{para_value};
    }

    if ($results) {

        #There are many attributes in v$dm_ini,here is just a part of it.
        $dmInfo->{CTL_PATH}       = $results->{CTL_PATH};
        $dmInfo->{CTL_BAK_PATH}   = $results->{CTL_BAK_PATH};
        $dmInfo->{CTL_BAK_NUM}    = $results->{CTL_BAK_NUM};
        $dmInfo->{CONFIG_PATH}    = $results->{CONFIG_PATH};
        $dmInfo->{MAX_OS_MEMORY}  = int( $results->{MAX_OS_MEMORY} );
        $dmInfo->{MEMORY_POOL}    = int( $results->{MEMORY_POOL} );
        $dmInfo->{WORKER_THREADS} = int( $results->{WORKER_THREADS} );
        $dmInfo->{TASK_THREADS}   = int( $results->{TASK_THREADS} );
        $dmInfo->{INSTANCE_NAME}  = $results->{INSTANCE_NAME};
    }

    return;
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

    my $dmInfo = {};
    $dmInfo->{MGMT_IP}       = $procInfo->{MGMT_IP};
    $dmInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');
    $dmInfo->{_MULTI_PROC}   = 1;

    #$dmInfo->{_MULTI_PROC}   = 1;

    #设置此采集到的对象对象类型，可以是：CollectObjCat->get('INS')，CollectObjCat->get('DBINS')，CollectObjCat::OS

    my $osUser  = $procInfo->{USER};
    my $command = $procInfo->{COMMAND};
    my $opts    = $self->parseCommandOpts($command);
    my $dmHome  = $opts->{dmHome};
    my $dmPath  = $opts->{dmPath};

    $dmInfo->{INSTALL_PATH} = $dmHome;
    $dmInfo->{DMINI_PATH}   = $opts->{path};

    my $port    = 5236;
    my $pFinder = $self->{pFinder};
    my ( $bizIp, $vip ) = $pFinder->predictBizIp( $connInfo, $port );

    $dmInfo->{PRIMARY_IP}   = $bizIp;
    $dmInfo->{VIP}          = $vip;
    $dmInfo->{PORT}         = $port;
    $dmInfo->{SERVICE_ADDR} = "$vip:$port";
    $dmInfo->{SSL_PORT}     = undef;

    my $host  = '127.0.0.1';
    my $disql = DisqlExec->new(
        dbHome => $dmHome,
        osUser => $osUser,
        host   => $host,
        port   => $port
    );
    $self->{disql} = $disql;

    my $version = $self->getInsVersion();
    if ( defined($version) and $version ne '' ) {
        $dmInfo->{VERSION} = $version;
    }
    else {
        $version = $self->getInsVersionByBinScriptFile($dmHome);
        $dmInfo->{VERSION} = $version;
    }

    $dmInfo->{ID_CODE}        = $self->getIdCode();
    $dmInfo->{EXPIRED_DATE}   = $self->getExpiredDate();
    $dmInfo->{USERS}          = $self->getUserInfo();
    $dmInfo->{TABLE_SPACESES} = $self->getTableSpaceInfo();

    $self->getDataBases( $disql, $dmInfo );
    $self->getParameters( $disql, $dmInfo );
    #############################

    #服务名, 要根据实际来设置
    $dmInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    my @collectSet = ();
    push( @collectSet, $dmInfo );
    push( @collectSet, @{ $dmInfo->{DATABASES} } );
    return @collectSet;
}

1;

