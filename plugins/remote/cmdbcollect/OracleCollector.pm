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

sub isCDB {
    my ($self) = @_;

    my $isCdb   = 0;
    my $sqlplus = $self->{sqlplus};
    my $sql     = 'show parameter enable_pluggable_database;';
    my $rows    = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );
    if ( defined($rows) and $$rows[0]->{VALUE} eq 'TRUE' ) {
        $isCdb = 1;
    }

    return $isCdb;
}

sub getVersion {
    my ( $self, $isRAC ) = @_;

    my $version = '';
    my $sqlplus = $self->{sqlplus};

    my $sql = q{select banner VERSION from v$version where rownum <=1;};
    if ( defined($isRAC) and $isRAC == 1 ) {
        $sql = q{select substr(BANNER,instr(BANNER,'Release',1)+7,11) VERSION from v$version where rownum <=1};
    }

    my $rows = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );
    if ( defined($rows) ) {
        $version = $$rows[0]->{VERSION};
    }

    return $version;
}

sub getUserInfo {
    my ( $self, $pdbName ) = @_;

    my $sqlplus = $self->{sqlplus};
    my $sql     = q{select du.username,du.default_tablespace from dba_users du where du.account_status='OPEN' and du.default_tablespace not in('SYSTEM','SYSAUX');};
    if ( defined($pdbName) and $pdbName ne '' ) {
        $sql = "alter session set container=$pdbName;\n$sql";
    }

    my @userInfos = ();
    my $rows      = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );
    foreach my $row (@$rows) {
        my $userInfo = {};
        $userInfo->{USERNAME}           = $row->{USERNAME};
        $userInfo->{DEFAULT_TABLESPACE} = $row->{DEFAULT_TABLESPACE};
        push( @userInfos, $userInfo );
    }

    return \@userInfos;
}

sub getTableSpaceInfo {
    my ( $self, $pdbName ) = @_;

    my $sqlplus = $self->{sqlplus};
    my $sql     = q{select tablespace_name, file_name, round(bytes/1024/1024/1024, 2) GIGA, autoextensible AUTOEX from dba_data_files};
    if ( defined($pdbName) and $pdbName ne '' ) {
        $sql = "alter session set container=$pdbName;\n$sql";
    }

    my $tableSpaces = {};
    my $rows        = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
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
    return \@allTableSpaces;
}

sub collectInstances {
    my ( $self, $insInfo ) = @_;

    my $sqlplus   = $self->{sqlplus};
    my $isVerbose = $self->{isVerbose};

    #获取CDB（pluggable database的标记）
    my $isCdb = $self->isCDB();
    $self->{isCdb}     = $isCdb;
    $insInfo->{IS_CDB} = $isCdb;

    my $dbId;
    my $logMode;
    my $rows = $sqlplus->query(
        sql     => 'select dbid,log_mode from v$database',
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        $dbId    = $$rows[0]->{DBID};
        $logMode = $$rows[0]->{LOG_MODE};
    }
    $insInfo->{DBID}     = $dbId;
    $insInfo->{LOG_MODE} = $logMode;

    $rows = $sqlplus->query(
        sql     => q{select name,value from v$parameter where name in ('cluster_database', 'db_name', 'db_unique_name', 'service_names','sga_max_size','log_archive_dest','log_archive_dest_1','memory_target')},
        verbose => $isVerbose
    );
    my $param = {};
    foreach my $row (@$rows) {
        $param->{ $row->{NAME} } = $row->{VALUE};
    }
    my $isRAC = 0;
    if ( $param->{cluster_database} eq 'TRUE' ) {
        $isRAC = 1;
    }
    $insInfo->{IS_RAC} = $isRAC;

    $insInfo->{SGA_MAX_SIZE}     = $param->{sga_max_size};
    $insInfo->{MEMORY_TARGET}    = $param->{memory_target};
    $insInfo->{LOG_ARCHIVE_DEST} = $param->{log_archive_dest_1};
    if ( not defined( $insInfo->{LOG_ARCHIVE_DEST} ) ) {
        $insInfo->{LOG_ARCHIVE_DEST} = $param->{log_archive_dest};
    }

    my $version;
    if ( $isCdb == 1 or $isRAC == 1 ) {
        $version = $self->getVersion(1);
    }
    else {
        $version = $self->getVersion();
    }
    $insInfo->{VERSION} = $version;

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
    $insInfo->{SERVICE_NAMES} = \@serviceNames;

    $rows = $sqlplus->query(
        sql     => q{select PARAMETER CHARACTERSET,VALUE from nls_database_parameters where PARAMETER='NLS_CHARACTERSET'},
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        $insInfo->{ $$rows[0]->{CHARACTERSET} } = $$rows[0]->{VALUE};
    }

    $insInfo->{USERS} = $self->getUserInfo();

    $insInfo->{TABLE_SPACESES} = $self->getTableSpaceInfo();

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

    my $procInfo = $self->{procInfo};
    $insInfo->{DISK_GROUPS} = \@diskGroups;
    $insInfo->{APP_TYPE}    = $procInfo->{APP_TYPE};
    $insInfo->{SERVER_NAME} = $insInfo->{INSTANCE_NAME};

    return $insInfo;
}

sub collectPDBS {

}

sub collectRAC {

}

sub collect {
    my ($self) = @_;
    $self->{isVerbose} = 1;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $insInfo = {};
    $insInfo->{OBJECT_TYPE} = $CollectObjType::DB;

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

    $insInfo->{ORACLE_HOME}     = $oraHome;
    $insInfo->{ORACLE_BASE}     = $oraBase;
    $insInfo->{ORACLE_HOSTNAME} = $oraHostname;
    $insInfo->{ORACLE_SID}      = $oraSid;
    $insInfo->{INSTANCE_NAME}   = $oraSid;

    my $sqlplus = SqlplusExec->new(
        sid     => $oraSid,
        osUser  => $oraUser,
        oraHome => $oraHome
    );

    #把sqlplus存到self属性里面，后续的方法会从self里获取sqlplus对象
    $self->{sqlplus} = $sqlplus;

    $self->collectInstances($insInfo);

    #ORACLE实例信息采集完成

    my @collectSet = ();
    push( @collectSet, $insInfo );

    #如果当前实例运行在CDB模式下，则采集CDB中的所有PDB
    if ( $insInfo->{IS_CDB} == 1 ) {
        my $PDBS = $self->collectPDBS();
        if ( defined($PDBS) ) {
            push( @collectSet, @$PDBS );
        }
    }

    #如果当前实例是RAC，则采集RAC信息，ORACLE集群信息
    if ( $insInfo->{IS_RAC} == 1 ) {
        my $racInfo = $self->collectRAC();
        if ( defined($racInfo) ) {
            push( @collectSet, $racInfo );
        }
    }

    return @collectSet;
}

1;
