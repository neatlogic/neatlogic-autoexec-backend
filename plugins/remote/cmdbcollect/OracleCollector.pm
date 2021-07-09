#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package OracleCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;
use SqlplusExec;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps  => ['\bora_pmon_'],            #正则表达是匹配ps输出
        psAttrs  => { COMM => 'oracle' },       #ps的属性的精确匹配
        envAttrs => { ORACLE_HOME => undef }    #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub getDeviceId {
    my ( $self, $devPath ) = @_;
    if ( defined($devPath) and -e $devPath ) {
        my $rdev  = ( stat($devPath) )[6];
        my $minor = $rdev % 256;
        my $major = int( $rdev / 256 );
        return "$major,$minor";
    }
    else {
        return undef;
    }
}

sub collect {
    my ($self) = @_;
    my $isVerbose = 1;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{OBJECT_TYPE} = $CollectObjType::DB;

    my $envMap = $procInfo->{ENVRIONMENT};

    my $oraUser = $procInfo->{USER};
    my $command = $procInfo->{COMMAND};
    my $oraSid  = $envMap->{ORACLE_SID};
    if ( $command =~ /^ora_pmon_(.*)$/ ) {
        $oraSid = $1;
    }

    my $oraHome     = $envMap->{ORACLE_HOME};
    my $oraBase     = $envMap->{ORACLE_BASE};
    my $oraHostname = $envMap->{ORACLE_HOSTNAME};

    $appInfo->{ORACLE_HOME}     = $oraHome;
    $appInfo->{ORACLE_BASE}     = $oraBase;
    $appInfo->{ORACLE_HOSTNAME} = $oraHostname;
    $appInfo->{ORACLE_SID}      = $oraSid;
    $appInfo->{INSTANCE_NAME}   = $oraSid;

    my $sqlplus = SqlplusExec->new(
        sid     => $oraSid,
        osUser  => $oraUser,
        oraHome => $oraHome
    );
    
    #获取CDB（pluggable database的标记）
    my $isCdb   = 0;
    my $version = '';
    my $rows    = $sqlplus->query(
        sql     => q{select substr(BANNER,instr(BANNER,'Release',1)+7,11) VERSION from v$version where rownum <=1},
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        $version = $$rows[0]->{VERSION};
    }
    $appInfo->{VERSION} = $version;

    # NAME    TYPE   VALUE
    # ------- ------ -------
    # db_name string orcl11g
    my $rows = $sqlplus->query(
        sql     => 'show parameter enable_pluggable_database',
        verbose => $isVerbose
    );
    if ( defined($rows) and $$rows[0]->{VALUE} eq 'TRUE' ) {
        $isCdb = 1;
    }
    $self->{isCdb}     = $isCdb;
    $appInfo->{IS_CDB} = $isCdb;

    my $dbId;
    my $logMode;
    $rows = $sqlplus->query(
        sql     => 'select dbid,log_mode from v$database',
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        $dbId    = $$rows[0]->{DBID};
        $logMode = $$rows[0]->{LOG_MODE};
    }

    $rows = $sqlplus->query(
        sql     => q{select name,value from v$parameter where name in ('cluster_database', 'db_name', 'db_unique_name', 'service_names','sga_max_size','log_archive_dest','log_archive_dest_1','memory_target')},
        verbose => $isVerbose
    );
    my $param = {};
    foreach my $row (@$rows) {
        $param->{ $row->{NAME} } = $row->{VALUE};
    }

    $appInfo->{SGA_MAX_SIZE}     = $param->{sga_max_size};
    $appInfo->{MEMORY_TARGET}    = $param->{memory_target};
    $appInfo->{LOG_ARCHIVE_DEST} = $param->{log_archive_dest_1};
    if ( not defined( $appInfo->{LOG_ARCHIVE_DEST} ) ) {
        $appInfo->{LOG_ARCHIVE_DEST} = $param->{log_archive_dest};
    }

    my $isRAC = 0;
    if ( $param->{cluster_database} eq 'TRUE' ) {
        $isRAC = 1;
    }
    $appInfo->{IS_RAC} = $isRAC;

    my $svcNameMap      = {};
    my $serviceNamesTxt = $param->{service_names};
    foreach my $oneSvcName ( split( /,/, $serviceNamesTxt ) ) {
        $svcNameMap->{$oneSvcName} = 1;
    }
    $rows = $sqlplus->query(
        sql     => q{select a.name from dba_services a,v$database b where b.DATABASE_ROLE='PRIMARY' and a.name not like 'SYS%'},
        verbose => $isVerbose
    );

    foreach my $row (@$rows) {
        $svcNameMap->{ $row->{NAME} } = 1;
    }
    my @serviceNames = keys(%$svcNameMap);
    $appInfo->{SERVICE_NAMES} = \@serviceNames;

    $rows = $sqlplus->query(
        sql     => q{select PARAMETER CHARACTERSET,VALUE from nls_database_parameters where PARAMETER='NLS_CHARACTERSET'},
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        $appInfo->{ $$rows[0]->{CHARACTERSET} } = $$rows[0]->{VALUE};
    }

    my @userInfos = ();
    $rows = $sqlplus->query(
        sql     => q{select  du.username,du.default_tablespace from dba_users du where du.account_status='OPEN' and du.default_tablespace not in('SYSTEM','SYSAUX')},
        verbose => $isVerbose
    );
    foreach my $row (@$rows) {
        my $userInfo = {};
        $userInfo->{USERNAME}           = $row->{USERNAME};
        $userInfo->{DEFAULT_TABLESPACE} = $row->{DEFAULT_TABLESPACE};
        push( @userInfos, $userInfo );
    }
    $appInfo->{USERS} = \@userInfos;

    my $tableSpaces = {};
    $rows = $sqlplus->query(
        sql     => q{select tablespace_name, file_name, round(bytes/1024/1024/1024, 2) GIGA, autoextensible AUTOEX from dba_data_files},
        verbose => $isVerbose
    );
    foreach my $row (@$rows) {
        my $dataFileInfo   = {};
        my $tableSpaceName = $row->{TABLESPACE_NAME};

        $dataFileInfo->{FILE_NAME}      = $row->{FILE_NAME};
        $dataFileInfo->{SIZE}           = $row->{GIGA} . 'G';
        $dataFileInfo->{AUTOEXTENSIBLE} = $row->{AUTOEX};

        my $tableSpace = $tableSpaces->{$tableSpaceName};
        if ( not defined($tableSpace) ) {
            $tableSpace = { TABLESPACE_NAME => $tableSpaceName, DATA_FILES => [] };
            $tableSpaces->{$tableSpaceName} = $tableSpace;
        }

        my $dataFiles = $tableSpace->{DATA_FILES};
        push( @$dataFiles, $dataFileInfo );
    }
    my @allTableSpaces = values(%$tableSpaces);
    $appInfo->{TABLE_SPACESES} = \@allTableSpaces;

    my @diskGroups;
    my $diskGroupsMap = {};
    $rows = $sqlplus->query(
        sql     => q{select name, type, total_mb, free_mb from v$asm_diskgroup},
        verbose => $isVerbose
    );
    foreach my $row (@$rows) {
        my $diskGroup = {};
        my $groupName = $row->{NAME};
        $diskGroup->{NAME}     = $groupName;
        $diskGroup->{TYPE}     = $row->{TYPE};
        $diskGroup->{TOTAL_MB} = $row->{TOTAL_MB};
        $diskGroup->{FREE_MB}  = $row->{FREE_MB};
        $diskGroup->{USAGE}    = sprintf( '.2f%', ( $row->{TOTAL_MB} - $row->{FREE_MB} ) * 100 / $row->{TOTAL_MB} );
        $diskGroup->{DISKS}    = [];
        push( @diskGroups, $diskGroup );
        $diskGroupsMap->{$groupName} = $diskGroup;
    }
    $rows = $sqlplus->query(
        sql     => q{select ad.name, adk.name groupname, ad.failgroup, ad.mount_status, ad.total_mb, ad.free_mb, ad.path from v$asm_disk ad,v$asm_diskgroup adk where ad.GROUP_NUMBER=adk.GROUP_NUMBER order by path},
        verbose => $isVerbose
    );
    foreach my $row (@$rows) {
        my $groupName = $row->{GROUPNAME};
        my $disks     = $diskGroupsMap->{$groupName}->{DISKS};
        my $disk      = {};
        $disk->{NAME}         = $row->{NAME};
        $disk->{FAIL_GROUP}   = $row->{FAILGROUP};
        $disk->{MOUNT_STATUS} = $row->{MOUNT_STATUS};
        $disk->{TOTAL_MB}     = $row->{TOTAL_MB};
        $disk->{FREE_MB}      = $row->{FREE_MB};
        $disk->{USAGE}        = sprintf( '.2f%', ( $row->{TOTAL_MB} - $row->{FREE_MB} ) * 100 / $row->{TOTAL_MB} );
        $disk->{PATH}         = $row->{PATH};

        my $asmDiskId = $self->getDeviceId( $row->{PATH} );
        $disk->{DEVICE_ID} = $asmDiskId;
        for my $devPath ( glob("/dev/*") ) {
            my $osDevId = $self->getDeviceId($devPath);
            if ( $osDevId eq $asmDiskId ) {
                my @diskStat = df($devPath);
                $disk->{LOGIC_DISK} = $devPath;
                last;
            }
        }

        push( @$disks, $disk );
    }
    $appInfo->{DISK_GROUPS} = \@diskGroups;

    #TODO：获取实例信息数据

    #默认的APP_TYPE是类名去掉Collector，如果要特殊的名称则自行设置
    $appInfo->{APP_TYPE}    = $procInfo->{APP_TYPE};
    $appInfo->{SERVER_NAME} = $appInfo->{INSTANCE_NAME};

    return $appInfo;
}

1;
