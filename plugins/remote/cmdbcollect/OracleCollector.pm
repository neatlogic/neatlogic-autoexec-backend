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

use Socket;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use SqlplusExec;

use JSON qw(to_json);

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps  => ['\bora_pmon_\w'],          #正则表达是匹配ps输出
                                                #psAttrs  => { COMM => 'oracle' },       #ps的属性的精确匹配
        envAttrs => { ORACLE_HOME => undef }    #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
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

sub getInsVersion {
    my ( $self, $insInfo ) = @_;

    my $version = '';
    my $sqlplus = $self->{sqlplus};

    my $sql = q{select REPLACE(banner_full, chr(10), ' ') VERSION from v$version where rownum <=1;};

    my $rows = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( not defined($rows) ) {
        $sql  = q{select banner VERSION from v$version where rownum <=1;};
        $rows = $sqlplus->query(
            sql     => $sql,
            verbose => $self->{isVerbose}
        );
    }

    if ( defined($rows) and scalar(@$rows) > 0 ) {
        $version = $$rows[0]->{VERSION};
        if ( $version =~ /\bVersion\s+([\d\.]+)/ or $version =~ /\bRelease\s+([\d\.]+)/ ) {
            $version = $1;
        }
    }

    return $version;
}

sub getUserInfo {
    my ( $self, $pdbName ) = @_;

    my $sqlplus = $self->{sqlplus};
    my $sql     = q{select du.username,du.default_tablespace from dba_users du where du.account_status='OPEN' and du.default_tablespace not in('SYSTEM','SYSAUX')};
    if ( defined($pdbName) and $pdbName ne '' ) {
        $sql = "alter session set container=$pdbName;\n$sql";
    }

    my @userInfos = ();
    my $rows      = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( defined($rows) ) {
        foreach my $row (@$rows) {
            my $userInfo = {};
            $userInfo->{USERNAME}           = $row->{USERNAME};
            $userInfo->{DEFAULT_TABLESPACE} = $row->{DEFAULT_TABLESPACE};
            push( @userInfos, $userInfo );
        }
    }

    return \@userInfos;
}

sub getTableSpaceInfo {
    my ( $self, $pdbName ) = @_;

    my $sqlplus = $self->{sqlplus};

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
    if ( defined($pdbName) and $pdbName ne '' ) {
        $sql = "alter session set container=$pdbName;\n$sql";
    }
    my $rows = $sqlplus->query(
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
    if ( defined($pdbName) and $pdbName ne '' ) {
        $sql = "alter session set container=$pdbName;\n$sql";
    }

    $rows = $sqlplus->query(
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
            if ( not defined($tableSpace) ) {
                $tableSpace = { NAME => $tableSpaceName, DATA_FILES => [] };
                $tableSpaces->{$tableSpaceName} = $tableSpace;
                $tableSpace->{AUTOEXTENSIBLE} = 'NO';
            }
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

sub getParams {
    my ( $self, $insInfo ) = @_;

    my $isVerbose = $self->{isVerbose};
    my $sqlplus   = $self->{sqlplus};

    my $dbId;
    my $databaseRole;
    my $logMode;
    my $rows = $sqlplus->query(
        sql     => 'select dbid,database_role,log_mode from v$database',
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        $dbId         = $$rows[0]->{DBID};
        $logMode      = $$rows[0]->{LOG_MODE};
        $databaseRole = $$rows[0]->{DATABASE_ROLE};
    }
    $insInfo->{DBID}          = $dbId;
    $insInfo->{LOG_MODE}      = $logMode;
    $insInfo->{DATABASE_ROLE} = $databaseRole;

    $rows = $sqlplus->query(
        sql     => q{select name,value from v$parameter where name in ('cluster_database', 'db_name', 'db_unique_name', 'service_names','sga_max_size','log_archive_dest','log_archive_dest_1','memory_target')},
        verbose => $isVerbose
    );
    my $param = {};
    if ( defined($rows) ) {
        foreach my $row (@$rows) {
            $param->{ $row->{NAME} } = $row->{VALUE};
        }
    }
    my $isRAC = 0;
    if ( $param->{cluster_database} eq 'TRUE' ) {
        $isRAC = 1;
    }
    $insInfo->{IS_RAC} = $isRAC;

    $insInfo->{DB_NAME}          = $param->{db_name};
    $insInfo->{SGA_MAX_SIZE}     = $param->{sga_max_size} + 0.0;
    $insInfo->{MEMORY_TARGET}    = $param->{memory_target};
    $insInfo->{LOG_ARCHIVE_DEST} = $param->{log_archive_dest_1};
    if ( not defined( $insInfo->{LOG_ARCHIVE_DEST} ) ) {
        $insInfo->{LOG_ARCHIVE_DEST} = $param->{log_archive_dest};
    }

    my $svcNameMap      = {};
    my @svcNames        = ();
    my $serviceNamesTxt = $param->{service_names};
    foreach my $oneSvcName ( split( /,/, $serviceNamesTxt ) ) {
        push( @svcNames, $oneSvcName );
        $svcNameMap->{$oneSvcName} = 1;
    }
    $insInfo->{SERVICE_NAMES} = \@svcNames;
    if ( scalar(@svcNames) > 0 ) {
        $insInfo->{SERVICE_NAME} = $svcNames[0];
    }

    $rows = $sqlplus->query(
        sql     => q{select PARAMETER,VALUE from nls_database_parameters where PARAMETER='NLS_CHARACTERSET'},
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        $insInfo->{NLS_CHARACTERSET} = $$rows[0]->{VALUE};
    }
}

sub getTcpInfo {
    my ( $self, $insInfo ) = @_;

    my $procInfo     = $insInfo->{PROC_INFO};
    my $oraSid       = $insInfo->{ORACLE_SID};
    my $serviceName  = $insInfo->{SERVICE_NAME};
    my $serviceNames = $insInfo->{SERVICE_NAMES};

    my $insNameToLsnrMap = $self->{insNameToLsnrMap};
    my $svcNameToLsnrMap = $self->{svcNameToLsnrMap};

    my @listeners = ();
    foreach my $svcName (@$serviceNames) {
        my $lsnrs = $svcNameToLsnrMap->{$svcName};
        if ( defined($lsnrs) ) {
            push( @listeners, @$lsnrs );
        }
    }

    if ( defined($oraSid) ) {
        my $lsnrs = $insNameToLsnrMap->{$oraSid};
        if ( defined($lsnrs) ) {
            push( @listeners, @$lsnrs );
        }
    }

    #把Oracle的listener的监听地址转换为进程的CONN_INFO
    my $svcNameMap     = {};
    my $allPorts       = {};
    my $miniPort       = 65535;
    my @listenAddrs    = ();
    my $listenMap      = {};
    my $listenPortsMap = {};
    foreach my $lsnrInfo (@listeners) {

        #listener数组里的lsnr可能是重复的，去掉已经分析过的
        my $lsnrName = $lsnrInfo->{NAME};
        if ( defined( $svcNameMap->{$lsnrName} ) ) {
            next;
        }
        $svcNameMap->{$lsnrName} = 1;

        my $lsnrPort = $lsnrInfo->{PORT};
        $allPorts->{$lsnrPort} = 1;
        if ( $lsnrPort < $miniPort ) {
            $miniPort = $lsnrPort;
        }
        foreach my $lsnAddr ( @{ $lsnrInfo->{LISTEN_ADDRS} } ) {
            $listenMap->{$lsnAddr} = 1;
        }
        foreach my $lsnPort ( @{ $lsnrInfo->{LISTEN_PORTS} } ) {
            $listenPortsMap->{$lsnPort} = 1;
        }
    }

    my $connInfo = $procInfo->{CONN_INFO};
    if ( not defined($connInfo) ) {
        $connInfo = { LISTEN => {} };
        $procInfo->{CONN_INFO} = $connInfo;
    }

    my $portsMap         = $connInfo->{LISTEN};
    my $tnsLsnrBaclogMap = $self->{tnsLsnrBaclogMap};
    foreach my $lsnrPort ( keys(%$listenPortsMap) ) {
        $portsMap->{$lsnrPort} = $tnsLsnrBaclogMap->{$lsnrPort};
    }

    @listenAddrs = keys(%$listenMap);
    $insInfo->{LISTEN_ADDRS} = \@listenAddrs;

    $insInfo->{PORT} = $miniPort;
    my @ports = sort( keys(%$allPorts) );
    $insInfo->{PORTS} = \@ports;
}

sub collectIns {
    my ( $self, $insInfo ) = @_;

    my $isVerbose = $self->{isVerbose};
    my $procInfo  = $self->{procInfo};
    my $osUser    = $procInfo->{USER};

    my $racInfo = $self->{RAC_INFO};

    $insInfo->{OS_USER} = $osUser;

    my $envMap = $procInfo->{ENVIRONMENT};

    my $oraHome = $envMap->{ORACLE_HOME};
    my $oraBase = $envMap->{ORACLE_BASE};

    if ( not defined($oraBase) or $oraBase eq '' ) {
        $oraBase = dirname($oraHome);
    }

    my $oraSid = $envMap->{ORACLE_SID};

    $insInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');
    $insInfo->{ORACLE_HOME}   = $oraHome;
    $insInfo->{ORACLE_BASE}   = $oraBase;
    $insInfo->{ORACLE_SID}    = $oraSid;
    $insInfo->{INSTANCE_NAME} = $oraSid;
    $insInfo->{INSTALL_PATH}  = $oraBase;
    $insInfo->{CONFIG_PATH}   = $oraBase;

    #把sqlplus存到self属性里面，后续的方法会从self里获取sqlplus对象
    $self->{sqlplus} = SqlplusExec->new(
        sid     => $oraSid,
        osUser  => $osUser,
        oraHome => $oraHome
    );

    #分析tsnrctl status的输出，生成服务名和实例名到listener的Map，后续的采集需要用到
    my ( $insNameToLsnrMap, $svcNameToLsnrMap ) = $self->getListenerInfo($insInfo);
    $self->{insNameToLsnrMap} = $insNameToLsnrMap;
    $self->{svcNameToLsnrMap} = $svcNameToLsnrMap;

    $self->getParams($insInfo);
    $self->getTcpInfo($insInfo);
    if ( $insInfo->{PORT} == 65535 ) {
        print("WARN: Can not find listen port for instance:$oraSid.\n");
        return undef;
    }

    my $version = $self->getInsVersion($insInfo);
    $insInfo->{VERSION} = $version;

    #获取CDB（pluggable database的标记）
    my $isCdb = $self->isCDB();
    $self->{isCdb}     = $isCdb;
    $insInfo->{IS_CDB} = $isCdb;

    $insInfo->{USERS}          = $self->getUserInfo();
    $insInfo->{TABLE_SPACESES} = $self->getTableSpaceInfo();

    $insInfo->{_OBJ_TYPE} = 'Oracle';
    $insInfo->{_APP_TYPE} = 'Oracle';

    if ( defined($racInfo) ) {
        if ( defined( $racInfo->{LOCAL_NODE_PUB_IP} ) ) {
            $insInfo->{IP} = $racInfo->{LOCAL_NODE_PUB_IP};
        }
        if ( defined( $racInfo->{LOCAL_NODE_VIP} ) ) {
            $insInfo->{VIP} = $racInfo->{LOCAL_NODE_VIP};
        }
    }

    $self->{INS_INFO} = $insInfo;
    return $insInfo;
}

sub collectCDB {
    my ( $self, $insInfo ) = @_;

    my $racInfo        = $self->{RAC_INFO};
    my $dbNameToDBInfo = $self->{dbNameToDBInfo};

    my $dbInfo      = {};
    my $dbName      = $insInfo->{DB_NAME};
    my $dbInRacInfo = $dbNameToDBInfo->{$dbName};
    if ( defined($dbInRacInfo) ) {
        map { $dbInfo->{$_} = $dbInRacInfo->{$_} } keys(%$dbInRacInfo);
    }
    map { $dbInfo->{$_} = $insInfo->{$_} } keys(%$insInfo);

    $dbInfo->{_OBJ_CATEGORY} = 'DB';
    $dbInfo->{_OBJ_TYPE}     = 'Oracle-DB';
    $dbInfo->{_APP_TYPE}     = 'DB';
    $dbInfo->{NOT_PROCESS}   = 1;
    $dbInfo->{RUN_ON}        = [];

    $dbInfo->{NAME} = $dbName;

    #采集instance对应的DB，可能是CDB或者是普通的DB
    if ( $insInfo->{IS_CDB} ) {
        $dbInfo->{_APP_TYPE} = 'CDB';
    }

    if ( $insInfo->{IS_RAC} == 1 ) {
        my $primaryIp;
        my @svcAddrs = ();
        my $scanIps  = $racInfo->{SCAN_IPS};
        my $scanPort = $racInfo->{SCAN_PORT};
        if ( defined($scanIps) and scalar(@$scanIps) > 0 ) {
            foreach my $scanIp (@$scanIps) {
                push( @svcAddrs, "$scanIp:$scanPort" );
            }
            $primaryIp = $$scanIps[0];
        }
        else {
            $primaryIp = $racInfo->{PRIMARY_IP};
        }

        my $svcAddr = join( ',', sort(@svcAddrs) );
        $dbInfo->{SERVICE_ADDR}  = $svcAddr;
        $dbInfo->{PRIMARY_IP}    = $primaryIp;
        $dbInfo->{VIP}           = $primaryIp;
        $dbInfo->{DATABASE_ROLE} = $insInfo->{DATABASE_ROLE};
    }
    else {
        $dbInfo->{PRIMARY_IP}    = $insInfo->{MGMT_IP};
        $dbInfo->{VIP}           = $dbInfo->{PRIMARY_IP};
        $dbInfo->{DATABASE_ROLE} = $insInfo->{DATABASE_ROLE};

        $dbInfo->{INSTANCES} = [
            {
                _OBJ_CATEGORY => 'DBINS',
                _OBJ_TYPE     => 'Oracle',
                INSTANCE_NAME => $insInfo->{INSTANCE_NAME},
                IP            => $insInfo->{IP},
                VIP           => $insInfo->{VIP},
                PORT          => $insInfo->{PORT},
                SERVICE_ADDR  => $insInfo->{SERVICE_ADDR}
            }
        ];
    }

    return [$dbInfo];
}

sub collectPDB {
    my ( $self, $insInfo ) = @_;

    my $racInfo        = $self->{RAC_INFO};
    my $dbName         = $insInfo->{DB_NAME};
    my $dbNameToDBInfo = $self->{dbNameToDBInfo};

    #获取所有的PDB信息
    my @pdbs    = ();
    my $sqlplus = $self->{sqlplus};
    my $sql     = q{select name,dbid,con_id from v$pdbs where name<>'PDB$SEED'};
    my $rows    = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );

    if ( defined($rows) ) {
        foreach my $row (@$rows) {
            my $pdb = {};

            my $dbInRacInfo = $dbNameToDBInfo->{$dbName};
            if ( defined($dbInRacInfo) ) {
                map { $pdb->{$_} = $dbInRacInfo->{$_} } keys(%$dbInRacInfo);
                $pdb->{PORT} = $racInfo->{SCAN_PORT};
            }
            else {
                $pdb->{INSTANCES} = [
                    {
                        _OBJ_CATEGORY => 'DBINS',
                        _OBJ_TYPE     => 'Oracle',
                        INSTANCE_NAME => $insInfo->{INSTANCE_NAME},
                        IP            => $insInfo->{IP},
                        VIP           => $insInfo->{VIP},
                        PORT          => $insInfo->{PORT},
                        SERVICE_ADDR  => $insInfo->{SERVICE_ADDR}
                    }
                ];
                $pdb->{PORT} = $insInfo->{PORT};
            }

            $pdb->{ORACLE_SID}  = $insInfo->{ORACLE_SID};
            $pdb->{ORACLE_HOME} = $insInfo->{ORACLE_HOME};
            $pdb->{ORACLE_BASE} = $insInfo->{ORACLE_BASE};

            $pdb->{NAME}   = $row->{NAME};
            $pdb->{DBID}   = $row->{DBID};
            $pdb->{CON_ID} = $row->{CON_ID};

            $pdb->{_OBJ_CATEGORY} = 'DB';
            $pdb->{_OBJ_TYPE}     = 'Oracle-DB';
            $pdb->{_APP_TYPE}     = 'PDB';
            $pdb->{CDB}           = $dbName;

            $pdb->{NOT_PROCESS} = 1;
            $pdb->{RUN_ON}      = [];

            push( @pdbs, $pdb );
        }
    }

    #获取PDB的service names
    foreach my $pdb (@pdbs) {
        my $pdbName = $pdb->{NAME};
        my $sql     = qq{alter session set container=$pdbName;\nselect name from V\$SERVICES;};
        my $rows    = $sqlplus->query(
            sql     => $sql,
            verbose => $self->{isVerbose}
        );
        my @serviceNames = ();
        if ( defined($rows) ) {
            foreach my $row (@$rows) {
                push( @serviceNames, $row->{NAME} );
            }
        }
        $pdb->{SERVICE_NAMES} = \@serviceNames;
        $pdb->{SERVICE_NAME}  = $serviceNames[0];

        if ( $insInfo->{IS_RAC} == 1 ) {
            my $primaryIp;
            my @svcAddrs = ();
            my $scanIps  = $racInfo->{SCAN_IPS};
            my $scanPort = $racInfo->{SCAN_PORT};
            if ( defined($scanIps) and scalar( (@$scanIps) ) > 0 ) {
                foreach my $scanIp (@$scanIps) {
                    push( @svcAddrs, "$scanIp:$scanPort" );
                }
                $primaryIp = $$scanIps[0];
            }
            else {
                $primaryIp = $racInfo->{PRIMARY_IP};
            }

            my $svcAddr = join( ',', sort(@svcAddrs) );
            $pdb->{SERVICE_ADDR} = $svcAddr;
            $pdb->{PRIMARY_IP}   = $primaryIp;
            $pdb->{VIP}          = $primaryIp;
        }
        else {
            $self->getTcpInfo($pdb);
            my $lsnAddrs = $pdb->{LISTEN_ADDRS};
            if ( defined($lsnAddrs) ) {
                my $svcAddr = join( ',', sort(@$lsnAddrs) );
                $pdb->{SERVICE_ADDR} = $svcAddr;
                $pdb->{PRIMARY_IP}   = $insInfo->{VIP};
                $pdb->{VIP}          = $pdb->{PRIMARY_IP};
            }
        }

        $pdb->{USERS}          = $self->getUserInfo($pdbName);
        $pdb->{TABLE_SPACESES} = $self->getTableSpaceInfo($pdbName);
    }

    return \@pdbs;
}

sub getGridVersion {
    my ( $self, $racInfo ) = @_;

    my $version = '';
    my $binPath = $racInfo->{GRID_HOME} . '/bin/crsd.bin';
    my $binStrs = $self->getCmdOut(qq{strings "$binPath"});
    if ( $binStrs =~ /-DBNRFULL_VERSION_STR="([\d\.]+)"/ ) {
        $version = $1;
    }
    $racInfo->{VERSION} = $version;
    return $version;
}

sub getClusterActiveVersion {
    my ( $self, $racInfo ) = @_;
    my $gridHome = $racInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    my $version;

    # $ crsctl query crs activeversion -f
    # Oracle Clusterware active version on the cluster is [12.1.0.0.2]. The cluster
    # upgrade state is [NORMAL]. The cluster active patch level is [456789126].
    ################
    #Oracle Clusterware active version on the cluster is [19.0.0.0.0]. The cluster upgrade state is [NORMAL]. The cluster active patch level is [3331580692].
    my $verDef = $self->getCmdOut( "$gridBin/crsctl query crs activeversion", $self->{gridUser} );
    if ( $verDef =~ /\[([\d\.]+)\]/s ) {
        $version = $1;
    }

    $racInfo->{CLUSTER_VERSION} = $version;
    return $version;
}

sub getASMDiskGroup {
    my ( $self, $racInfo ) = @_;

    my $sqlplus   = $self->{sqlplus};
    my $isVerbose = $self->{isVerbose};

    my @diskGroups    = ();
    my $diskGroupsMap = {};
    my $rows          = $sqlplus->query(
        sql     => q{select name, type, total_mb, free_mb from v$asm_diskgroup},
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        foreach my $row (@$rows) {
            my $diskGroup = {};
            my $groupName = $row->{NAME};
            $diskGroup->{NAME}     = $groupName;
            $diskGroup->{TYPE}     = $row->{TYPE};
            $diskGroup->{TOTAL}    = int( $row->{TOTAL_MB} * 1000 / 1024 + 0.5 ) / 1000;
            $diskGroup->{FREE}     = int( $row->{FREE_MB} * 1000 / 1024 + 0.5 ) / 1000;
            $diskGroup->{USED}     = $diskGroup->{TOTAL} - $diskGroup->{FREE};
            $diskGroup->{USED_PCT} = sprintf( '.2f%', ( $row->{TOTAL_MB} - $row->{FREE_MB} ) * 100 / $row->{TOTAL_MB} ) + 0.0;
            $diskGroup->{DISKS}    = [];
            push( @diskGroups, $diskGroup );
            $diskGroupsMap->{$groupName} = $diskGroup;
        }
    }
    $rows = $sqlplus->query(
        sql     => q{select ad.name, adk.name gname, ad.failgroup fgroup, ad.mount_status mnt_sts, ad.total_mb, ad.free_mb, ad.path from v$asm_disk ad,v$asm_diskgroup adk where ad.GROUP_NUMBER=adk.GROUP_NUMBER order by path},
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        foreach my $row (@$rows) {
            my $groupName = $row->{GNAME};
            my $disks     = $diskGroupsMap->{$groupName}->{DISKS};
            my $disk      = {};
            $disk->{NAME}         = $row->{NAME};
            $disk->{FAIL_GROUP}   = $row->{FGROUP};
            $disk->{MOUNT_STATUS} = $row->{MNT_STS};
            $disk->{CAPACITY}     = int( $row->{TOTAL_MB} * 1000 / 1024 + 0.5 ) / 1000 + 0.0;
            $disk->{FREE}         = int( $row->{FREE_MB} * 1000 / 1024 + 0.5 ) / 1000 + 0.0;
            $disk->{USED}         = $disk->{CAPACITY} - $disk->{FREE};
            $disk->{USED_PCT}     = sprintf( '.2f%', ( $row->{TOTAL_MB} - $row->{FREE_MB} ) * 100 / $row->{TOTAL_MB} ) + 0.0;
            $disk->{DEV_PATH}     = $row->{PATH};

            push( @$disks, $disk );
        }
    }

    $racInfo->{DISK_GROUPS} = \@diskGroups;
    return \@diskGroups;
}

sub getClusterDB {
    my ( $self, $racInfo, $dbNodesMap, $svcNameToScanLsnrMap, $svcNameToLsnrMap ) = @_;
    my $gridHome = $racInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    my $allIpMap  = {};
    my $scanName  = $racInfo->{SCAN_NAME};
    my $scanIps   = $racInfo->{SCAN_IPS};
    my $scanPort  = $racInfo->{SCAN_PORT};
    my @scanAddrs = ();
    foreach my $scanIp (@$scanIps) {
        $allIpMap->{$scanIp} = 1;
        push( @scanAddrs, "$scanIp:$scanPort" );
    }

    # $ srvctl config database
    # orcl1
    # orcl2
    my $dbNamesLines = $self->getCmdOutLines( "$gridBin/srvctl config database", $self->{gridUser} );
    my @dbNames;
    foreach my $dbName (@$dbNamesLines) {
        $dbName =~ s/^\s*|\s*$//g;
        if ( $dbName ne '' ) {
            push( @dbNames, $dbName );
        }
    }

    my $tnsLsnrBaclogMap = $self->{tnsLsnrBaclogMap};

    my @nodeAddrs = ();
    my @dbInfos   = ();
    foreach my $dbName (@dbNames) {
        my $dbInfo = {
            _OBJ_CATEGORY => 'DB',
            _OBJ_TYPE     => 'Oracle-DB',
            NAME          => $dbName
        };

        my $miniPort    = 65535;
        my @listenAddrs = ();
        my $listenMap   = {};
        my $lsnrs       = $svcNameToLsnrMap->{$dbName};
        foreach my $lsnrInfo (@$lsnrs) {
            if ( $lsnrInfo->{PORT} < $miniPort ) {
                $miniPort = $lsnrInfo->{PORT};
            }
            foreach my $lsnAddr ( @{ $lsnrInfo->{LISTEN_ADDRS} } ) {
                $listenMap->{$lsnAddr} = $tnsLsnrBaclogMap->{$lsnAddr};
                push( @listenAddrs, $lsnAddr );
            }
            foreach my $lsnAddr (@scanAddrs) {
                $listenMap->{$lsnAddr} = $tnsLsnrBaclogMap->{$lsnAddr};
                push( @listenAddrs, $lsnAddr );
            }
        }
        if ( $miniPort == 65535 ) {
            print("WARN: Can not find listen port for db:$dbName.\n");
            next;
        }
        $dbInfo->{PORT}                = $miniPort;
        $dbInfo->{LISTEN_ADDRS}        = \@listenAddrs;
        $dbInfo->{DB_LISTEN_PORTS_MAP} = $listenMap;

        if ( scalar(@scanAddrs) > 0 ) {
            $dbInfo->{SCAN_ADDRS} = \@scanAddrs;
        }

        my $tnsAddrs;
        if ( scalar(@scanAddrs) > 0 ) {
            $tnsAddrs = "$scanName:$scanPort";
            $dbInfo->{SERVICE_ADDR} = "$scanName:$scanPort";
        }

        my @nodes     = ();
        my @instances = ();

        #Instance ASKMDB1 is not running on node exaaskmdb01
        #Instance ASKMDB2 is running on node exaaskmdb02
        my ( $status, $outLines ) = $self->getCmdOutLines( "$gridBin/srvctl status database -d '$dbName' -f", $self->{gridUser} );
        if ( $status == 0 and defined($outLines) ) {
            foreach my $line (@$outLines) {
                if ( $line =~ /Instance\s+(.+)\s+is.*?\son\s+node\s+(.+)\s*/ ) {
                    my $instanceName = $1;
                    my $nodeName     = $2;
                    push( @nodes, $nodeName );
                    my $nodeInfo = $dbNodesMap->{$nodeName};
                    push(
                        @instances,
                        {
                            _OBJ_CATEGORY => 'DBINS',
                            _OBJ_TYPE     => 'Oracle',
                            NAME          => $instanceName,
                            NODE_NAME     => $nodeName,
                            IP            => $nodeInfo->{IP},
                            VIP           => $nodeInfo->{VIP},
                            PORT          => $miniPort,
                            SERVICE_ADDR  => $nodeInfo->{IP} . ':' . $miniPort
                        }
                    );
                }
            }

            $dbInfo->{INSTANCES} = \@instances;

            my @svcIps      = ();
            my @insSvcAddrs = ();
            foreach my $insInfo (@instances) {
                if ( defined( $insInfo->{VIP} and $insInfo->{VIP} ne '' ) ) {
                    $allIpMap->{ $insInfo->{VIP} } = 1;
                    push( @svcIps,      $insInfo->{VIP} );
                    push( @insSvcAddrs, $insInfo->{VIP} . ':' . $insInfo->{PORT} );
                }
                elsif ( defined( $insInfo->{IP} ) and $insInfo->{IP} ne '' ) {
                    $allIpMap->{ $insInfo->{IP} } = 1;
                    push( @svcIps,      $insInfo->{IP} );
                    push( @insSvcAddrs, $insInfo->{IP} . ':' . $insInfo->{PORT} );
                }
            }
            @svcIps = sort(@svcIps);

            if ( scalar(@$scanIps) > 0 ) {
                $dbInfo->{PRIMARY_IP}   = $$scanIps[0];
                $dbInfo->{VIP}          = $$scanIps[0];
                $dbInfo->{CAN_IP_FLOAT} = 1;
            }
            elsif ( scalar(@svcIps) > 0 ) {
                $dbInfo->{PRIMARY_IP}   = $svcIps[0];
                $dbInfo->{VIP}          = $svcIps[0];
                $dbInfo->{CAN_IP_FLOAT} = 0;
            }
            else {
                print("WARN: Can not dtermine the primary ip for db:$dbName.\n");
                $dbInfo->{PRIMARY_IP}   = undef;
                $dbInfo->{VIP}          = undef;
                $dbInfo->{CAN_IP_FLOAT} = 0;
            }

            if ( not defined($tnsAddrs) ) {
                $tnsAddrs = join( ',', sort(@insSvcAddrs) );
                $dbInfo->{SERVICE_ADDR} = $tnsAddrs;
            }

            my $primaryIp = $dbInfo->{PRIMARY_IP};
            delete( $allIpMap->{$primaryIp} );
            my @slaveIps = sort( keys(%$allIpMap) );
            $dbInfo->{SLAVE_IPS} = \@slaveIps;

            push( @dbInfos, $dbInfo );
        }
    }

    return \@dbInfos;
}

sub getClusterName {
    my ( $self, $racInfo ) = @_;
    my $gridHome = $racInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    # [root@rac1 bin]# ./olsnodes -c
    # crs
    my $clusterName = $self->getCmdOut( "$gridBin/olsnodes -c", $self->{gridUser} );
    $clusterName =~ s/^\s*|\s*$//g;
    $racInfo->{CLUSTER_NAME} = $clusterName;
    $racInfo->{NAME}         = $clusterName;
}

sub getClusterLocalNode {
    my ( $self, $racInfo ) = @_;
    my $gridHome = $racInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    #olsnodes -l #get local node
    my $node = $self->getCmdOut( "$gridBin/olsnodes -l", $self->{gridUser} );
    $node =~ s/^\s*|\s*$//g;
    return $node;
}

sub getClusterNodes {
    my ( $self, $racInfo ) = @_;
    my $gridHome = $racInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    # [root@node1]# olsnodes
    # node1
    # node2
    # node3
    # node4
    my $dbNodesMap   = {};
    my @nodePubIps   = ();
    my $dbNodesLines = $self->getCmdOutLines( "$gridBin/olsnodes", $self->{gridUser} );
    my @dbNodes      = ();
    foreach my $dbNode (@$dbNodesLines) {
        $dbNode =~ s/^\s*|\s*$//g;
        if ( $dbNode ne '' ) {
            my $ipAddr    = gethostbyname($dbNode);
            my $nodePubIp = inet_ntoa($ipAddr);
            my $nodeInfo  = { _OBJ_CATEGORY => 'OS', _OBJ_TYPE => $self->{ostype}, NAME => $dbNode, IP => $nodePubIp };
            $self->getNodeVip( $racInfo, $nodeInfo );
            $self->getNodePrivNet( $racInfo, $nodeInfo );
            $nodeInfo->{HOST_ON} = { _OBJ_TYPE => $self->{ostype}, HOST => $nodePubIp, MGMT_IP => $nodePubIp };
            push( @nodePubIps, $nodePubIp );
            push( @dbNodes,    $nodeInfo );
            $dbNodesMap->{$dbNode} = $nodeInfo;
        }
    }

    $racInfo->{NODES}      = \@dbNodes;
    $racInfo->{PRIMARY_IP} = shift(@nodePubIps);
    $racInfo->{SLAVE_IPS}  = \@nodePubIps;

    return $dbNodesMap;
}

sub getNodePrivNet {
    my ( $self, $racInfo, $nodeInfo ) = @_;
    my $gridHome = $racInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    my $privNet;
    my $privInfoLines = $self->getCmdOutLines( "$gridBin/oifcfg getif", $self->{gridUser} );
    foreach my $line (@$privInfoLines) {
        if ( $line =~ /cluster_interconnect/ and $line =~ /([\.:a-fA-f0-9]{4,})/ ) {
            $privNet = $1;
        }
    }
    $nodeInfo->{PRIV_NET} = $privNet;
}

sub getNodeVip {
    my ( $self, $racInfo, $nodeInfo ) = @_;
    my $gridHome = $racInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    my $nodeName = $nodeInfo->{NAME};
    my $vipName;
    my $nodeVip;

    # [oracle@node-rac1 ~]$ srvctl config nodeapps -n node-rac2
    # VIP exists.: /node-vip2/192.168.12.240/255.255.255.0/eth0
    # GSD exists.
    #############################
    # VIP exists: network number 1, hosting node edbassb1p
    # VIP Name: edbassb1p-vip
    # VIP IPv4 Address: 10.0.13.122
    # VIP IPv6 Address:
    # VIP is enabled.
    # VIP is individually enabled on nodes:
    # VIP is individually disabled on nodes:
    my $nodeVipInfoLines = $self->getCmdOutLines( "$gridBin/srvctl config vip -node $nodeName", $self->{gridUser} );
    foreach my $line (@$nodeVipInfoLines) {
        if ( $line =~ /VIP Name:\s*(\S+)$/ ) {
            $vipName = $1;
        }
        elsif ( $line =~ /VIP\s+IPv4\s+Address:\s*([\d\.]+)/ ) {
            $nodeVip = $1;
        }
        elsif ( $line =~ /VIP\s+IPv6\s+Address:\s*([:a-fA-f0-9]+)/ ) {
            $nodeVip = $1;
        }
        elsif ( $line =~ qr{/.*?/([\.:a-fA-f0-9]+)/.*?/.*?/.*?, hosting node (.*)} ) {
            $nodeVip = $1;
        }
        elsif ( $line =~ qr{VIP exists\.:\s*/.*?/([\.:a-fA-f0-9]+)/.*?/.*?} ) {
            $nodeVip = $1;
        }
    }
    $nodeInfo->{VIP_NAME} = $vipName;
    $nodeInfo->{VIP}      = $nodeVip;

    return $nodeVip;
}

sub getScanInfo {
    my ( $self, $racInfo ) = @_;
    my $gridHome = $racInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    # [grid@rac1 ~]$ srvctl config scan_listener
    # SCAN Listeners for network 1:
    # Registration invited nodes:
    # Registration invited subnets:
    # Endpoints: TCP:1521
    # SCAN Listener LISTENER_SCAN1 exists
    # SCAN Listener is enabled.
    my $scanPort;
    my $scanPortLines = $self->getCmdOutLines( "$gridBin/srvctl config scan_listener", $self->{gridUser} );
    foreach my $line (@$scanPortLines) {
        if ( $line =~ /TCP:\s*(\d+)/i ) {
            $scanPort = int($1);
            last;
        }
    }

    my $scanName;
    my @scanIps = ();

    # [grid@rac2 ~]$ srvctl config scan
    # SCAN name: racnode-cluster-scan.racnode.com, Network: 1/192.168.3.0/255.255.255.0/eth0
    # SCAN VIP name: scan1, IP: /racnode-cluster-scan.racnode.com/192.168.3.231
    # SCAN VIP name: scan2, IP: /racnode-cluster-scan.racnode.com/192.168.3.233
    # SCAN VIP name: scan3, IP: /racnode-cluster-scan.racnode.com/192.168.3.232
    my $scanInfoLines = $self->getCmdOutLines( "$gridBin/srvctl config scan", $self->{gridUser} );
    foreach my $line (@$scanInfoLines) {
        if ( $line =~ /SCAN name:\s*([^\s,]+)/ ) {
            $scanName = $1;
        }
        elsif ( $line =~ /VIP.*?([\.\d:a-f]{4,})/i ) {
            push( @scanIps, $1 );
        }
    }
    @scanIps              = sort(@scanIps);
    $racInfo->{SCAN_NAME} = $scanName;
    $racInfo->{SCAN_IPS}  = \@scanIps;
    $racInfo->{SCAN_PORT} = $scanPort;
}

# Listening Endpoints Summary...
#   (DESCRIPTION=(ADDRESS=(PROTOCOL=ipc)(KEY=LISTENER_SCAN2)))
#   (DESCRIPTION=(ADDRESS=(PROTOCOL=tcp)(HOST=192.168.1.170)(PORT=1521)))
# Services Summary...
# Service "grac4" has 3 instance(s).
#   Instance "grac41", status READY, has 1 handler(s) for this service...
#   Instance "grac42", status READY, has 1 handler(s) for this service...
#   Instance "grac43", status READY, has 1 handler(s) for this service...
# Service "grac41" has 1 instance(s).
#   Instance "grac41", status READY, has 1 handler(s) for this service...
# Service "grac42" has 1 instance(s).
#   Instance "grac42", status READY, has 1 handler(s) for this service...
# Service "grac43" has 1 instance(s).
#   Instance "grac43", status READY, has 1 handler(s) for this service...
# Service "grac4XDB" has 3 instance(s).
#   Instance "grac41", status READY, has 1 handler(s) for this service...
#   Instance "grac42", status READY, has 1 handler(s) for this service...
#   Instance "grac43", status READY, has 1 handler(s) for this service...
# Service "report" has 1 instance(s).
#   Instance "grac42", status READY, has 1 handler(s) for this service...
# The command completed successfully
sub parseListenerInfo {
    my ( $self, $outLines, $lsnrName, $serviceNameToLsnrMap, $insNameToLsnrMap ) = @_;

    my $lsnPortsMap = {};

    my $lsnrInfo     = { NAME => $lsnrName };
    my $miniPort     = 65536;
    my @serviceNames = ();
    my @listenAddrs  = ();
    my $servicesMap  = ();
    for ( my $i = 0 ; $i < scalar(@$outLines) ; $i++ ) {
        my $line = $$outLines[$i];

        # Listening Endpoints Summary...
        if ( $line =~ /^Listening Endpoints Summary\.\.\./ ) {
            $i++;
            $line = $$outLines[$i];

            #   (DESCRIPTION=(ADDRESS=(PROTOCOL=ipc)(KEY=LISTENER_SCAN2)))
            while ( $line =~ /^\s*\(DESCRIPTION=\(ADDRESS=\(PROTOCOL=/i ) {
                if ( $line =~ /\(PORT=(\d+)\)/ ) {
                    my $port = int($1);

                    my @ips = ();
                    my $ip;
                    if ( $line =~ /\(HOST=(.*?)\)/ ) {
                        my $host = $1;
                        if ( $host !~ /^[\d\.]+$/ ) {
                            foreach my $ipAddr ( ( gethostbyname($host) )[4] ) {
                                push( @ips, inet_ntoa($ipAddr) );
                            }
                        }
                        else {
                            push( @ips, $host );
                        }
                    }
                    if ( scalar(@ips) == 0 ) {
                        push( @ips, '*' );
                    }

                    if ( $port < $miniPort ) {
                        $miniPort = $port;
                    }

                    foreach my $ip (@ips) {
                        push( @listenAddrs, "$ip:$port" );
                        if ( $ip ne '*' and $ip ne '0' and $ip ne '::' and $ip ne '' ) {
                            $lsnPortsMap->{"$ip:$port"} = 1;
                        }
                        else {
                            $lsnPortsMap->{$port} = 1;
                        }
                    }
                }

                $i++;
                $line = $$outLines[$i];
            }
            $i--;
        }

        # Service "grac4" has 3 instance(s).
        elsif ( $line =~ /^Service "(.*?)" has \d+ instance\(s\)\./ ) {
            $i++;
            $line = $$outLines[$i];

            my $serviceName = $1;
            my $lsnrs       = $serviceNameToLsnrMap->{$serviceName};
            if ( not defined($lsnrs) ) {
                $serviceNameToLsnrMap->{$serviceName} = [$lsnrInfo];
            }
            else {
                push( @$lsnrs, $lsnrInfo );
            }
            push( @serviceNames, $serviceName );

            if ( defined($insNameToLsnrMap) ) {
                while ( $line =~ /Instance "(.*?)"/ ) {
                    my $insName = $1;
                    $insNameToLsnrMap->{$insName} = [$lsnrInfo];

                    $i++;
                    $line = $$outLines[$i];
                }
                $i--;
            }
        }
    }

    if ( $miniPort == 65535 ) {
        return undef;
    }

    $lsnrInfo->{PORT}          = $miniPort;
    $lsnrInfo->{LISTEN_ADDRS}  = \@listenAddrs;
    $lsnrInfo->{SERVICE_NAMES} = \@serviceNames;

    my @lsnrPorts = keys(%$lsnPortsMap);
    $lsnrInfo->{LISTEN_PORTS} = \@lsnrPorts;

    return $lsnrInfo;
}

sub getScanListenerInfo {
    my ( $self, $racInfo ) = @_;
    my $gridHome = $racInfo->{GRID_HOME};
    my $gridUser = $self->{gridUser};

    # srvctl status  scan_listener
    # SCAN Listener LISTENER_SCAN1 is enabled
    # SCAN listener LISTENER_SCAN1 is running on node grac2
    # SCAN Listener LISTENER_SCAN2 is enabled
    # SCAN listener LISTENER_SCAN2 is running on node grac1
    # SCAN Listener LISTENER_SCAN3 is enabled
    # SCAN listener LISTENER_SCAN3 is running on node grac1

    #获取其中一个Listener，通过lsnrctl获取service names信息
    my $lsnrNamesMap = {};
    my ( $listener, $enableListener, $activeListener );
    my $scanStatusLines = $self->getCmdOutLines( "LANG=en_US.UTF-8 $gridHome/bin/srvctl status scan_listener", $gridUser );
    foreach my $line (@$scanStatusLines) {
        if ( $line =~ /^SCAN listener (.*?) is running/i ) {
            $activeListener = $1;
            $lsnrNamesMap->{$activeListener} = 1;
        }
        elsif ( $line =~ /^SCAN Listener (.*?) is enabled/i ) {
            $enableListener = $1;
            $lsnrNamesMap->{$enableListener} = 1;
        }
    }
    my @lsnrNames = keys(%$lsnrNamesMap);

    my $serviceNameToLsnrMap = {};
    my @listeners            = ();
    foreach my $lsnrName (@lsnrNames) {
        my $outLines = $self->getCmdOutLines( "LANG=en_US.UTF-8 $gridHome/bin/lsnrctl status $lsnrName", $gridUser );
        my $lsnrInfo = $self->parseListenerInfo( $outLines, $lsnrName, $serviceNameToLsnrMap );
        if ( not defined($lsnrInfo) ) {
            next;
        }
        push( @listeners, $lsnrInfo );

        my $lsnrPorts = $lsnrInfo->{LISTEN_PORTS};
        my $procInfo  = $racInfo->{PROC_INFO};
        my $portsMap  = $procInfo->{CONN_INFO}->{LISTEN};

        my $tnsLsnrBaclogMap = $self->{tnsLsnrBaclogMap};
        foreach my $lsnrPort (@$lsnrPorts) {
            $portsMap->{$lsnrPort} = $tnsLsnrBaclogMap->{$lsnrPort};
        }
    }
    $racInfo->{SCAN_LISTENERS} = \@listeners;

    return $serviceNameToLsnrMap;
}

sub getListenerInfo {
    my ( $self, $info ) = @_;
    my $gridHome = $info->{GRID_HOME};
    if ( not defined($gridHome) or $gridHome eq '' ) {
        $gridHome = $info->{ORACLE_HOME};
    }
    my $osUser = $info->{GRID_USER};
    if ( not defined($osUser) or $osUser eq '' ) {
        $osUser = $info->{OS_USER};
    }

    # srvctl status listener
    # Listener LISTENER is enabled
    # Listener LISTENER is running on node(s): rac1,rac2
    # Listener LISTENER_TEST is enabled
    # Listener LISTENER_TEST is running on node(s): rac1,rac2

    #获取其中一个Listener，通过lsnrctl获取service names信息
    my $lsnrNamesMap = {};
    my $listener;
    my $tnslsnrLines = $self->getCmdOutLines("ps -u $osUser -o args |grep tnslsnr");
    foreach my $line (@$tnslsnrLines) {
        if ( $line =~ /\btnslsnr\s+(\S+)\s+/ ) {
            $lsnrNamesMap->{$1} = 1;
        }
    }
    my @lsnrNames = keys(%$lsnrNamesMap);

    my $tnsLsnrBaclogMap     = $self->{tnsLsnrBaclogMap};
    my $serviceNameToLsnrMap = {};
    my $insNameToLsnrMap     = {};
    my @listeners            = ();
    foreach my $lsnrName (@lsnrNames) {
        my $outLines = $self->getCmdOutLines( "LANG=en_US.UTF-8 $gridHome/bin/lsnrctl status $lsnrName", $osUser );
        my $lsnrInfo = $self->parseListenerInfo( $outLines, $lsnrName, $serviceNameToLsnrMap, $insNameToLsnrMap );
        if ( not defined($lsnrInfo) ) {
            next;
        }
        push( @listeners, $lsnrInfo );

        my $lsnrPorts = $lsnrInfo->{LISTEN_PORTS};
        my $procInfo  = $info->{PROC_INFO};
        my $portsMap  = $procInfo->{CONN_INFO}->{LISTEN};

        foreach my $lsnrPort (@$lsnrPorts) {
            $portsMap->{$lsnrPort} = $tnsLsnrBaclogMap->{$lsnrPort};
        }
    }
    $info->{LISTENERS} = \@listeners;

    return ( $insNameToLsnrMap, $serviceNameToLsnrMap );
}

sub collectRAC {
    my ( $self, $racInfo ) = @_;
    $self->{isVerbose} = 1;

    my $procInfo         = $racInfo->{PROC_INFO};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    my $envMap           = $procInfo->{ENVIRONMENT};

    my $osUser  = $procInfo->{USER};
    my $comm    = $procInfo->{COMM};
    my $command = $procInfo->{COMMAND};
    my $oraSid  = $envMap->{ORACLE_SID};

    $self->{gridUser}     = $osUser;
    $racInfo->{GRID_USER} = $osUser;
    print("INFO: Oracle SID: $oraSid.\n");

    my $oraHome = $envMap->{ORACLE_HOME};
    my $oraBase = $envMap->{ORACLE_BASE};

    $racInfo->{_OBJ_CATEGORY}    = CollectObjCat->get('CLUSTER');
    $racInfo->{_OBJ_TYPE}        = 'DBCluster';
    $racInfo->{_APP_TYPE}        = 'Oracle';
    $racInfo->{CLUSTER_MODE}     = 'RAC';
    $racInfo->{CLUSTER_SOFTWARE} = 'Oracle Grid';

    $racInfo->{ORACLE_HOME}  = $oraHome;
    $racInfo->{ORACLE_BASE}  = $oraBase;
    $racInfo->{GRID_HOME}    = $oraHome;
    $racInfo->{GRID_BASE}    = $oraBase;
    $racInfo->{INSTALL_PATH} = $oraHome;
    $racInfo->{CONFIG_PATH}  = $oraBase;

    my $localNode = $self->getClusterLocalNode($racInfo);
    if ( not defined($localNode) ) {
        print("WARN: This host is not oracle rac node.\n");
        return undef;
    }

    my $sqlplus = SqlplusExec->new(
        sid     => $oraSid,
        osUser  => $osUser,
        oraHome => $oraHome,
        sysasm  => 1
    );

    #把sqlplus存到self属性里面，后续的方法会从self里获取sqlplus对象
    $self->{sqlplus} = $sqlplus;

    my $gridHome = $racInfo->{GRID_HOME};
    my $gridBase = $racInfo->{GRID_BASE};

    $self->{srvctlPath} = File::Spec->canonpath("$gridHome/bin/srvctl");

    my $dbNodesMap = $self->getClusterNodes($racInfo);
    my $localNode  = $self->getClusterLocalNode($racInfo);
    $racInfo->{LOCAL_NODE} = $localNode;

    my $nodes = $racInfo->{NODES};
    if ( $$nodes[0]->{NAME} ne $localNode ) {
        print("WARN: Rac node:$localNode is not primary node, no need to collect.\n");
        return undef;
    }

    my $localNodePubIp;
    my $localNodeVip;
    foreach my $nodeInfo (@$nodes) {
        if ( $nodeInfo->{NAME} eq $localNode ) {
            $localNodePubIp = $nodeInfo->{IP};
            $localNodeVip   = $nodeInfo->{VIP};
            last;
        }
    }
    $racInfo->{LOCAL_NODE_PUB_IP} = $localNodePubIp;
    $racInfo->{LOCAL_NODE_VIP}    = $localNodeVip;

    $self->getClusterName($racInfo);
    $self->getGridVersion($racInfo);
    $self->getClusterActiveVersion($racInfo);
    $self->getScanInfo($racInfo);
    $self->getASMDiskGroup($racInfo);

    my $scanIps = $racInfo->{SCAN_IPS};
    if ( defined($scanIps) and (@$scanIps) > 0 ) {
        $racInfo->{PRIMARY_IP} = $$scanIps[0];
    }

    my $svcNameToLsnrMap     = $self->getListenerInfo($racInfo);
    my $svcNameToScanLsnrMap = $self->getScanListenerInfo($racInfo);

    my $databases = $self->getClusterDB( $racInfo, $dbNodesMap, $svcNameToScanLsnrMap, $svcNameToLsnrMap );
    $racInfo->{DATABASES} = $databases;

    my @collectSet = ();
    push( @collectSet, $racInfo );
    $self->{RAC_INFO} = $racInfo;

    my $dbNameToDBInfo = {};
    $self->{dbNameToDBInfo} = $dbNameToDBInfo;

    my @collectDatabases = ();
    my $instanceMap      = {};
    foreach my $database (@$databases) {
        my $collectDatabase = {};
        map { $collectDatabase->{$_} = $database->{$_} } keys(%$database);
        delete( $database->{DB_LISTEN_PORTS_MAP} );
        $collectDatabase->{NOT_PROCESS} = 1;
        $collectDatabase->{RUN_ON}      = [];
        $collectDatabase->{PROC_INFO}   = {
            PID       => $procInfo->{PID},
            PPID      => $procInfo->{PPID},
            CONN_INFO => {
                LISTEN => delete( $collectDatabase->{DB_LISTEN_PORTS_MAP} ),
                PEER   => {}
            }
        };

        push( @collectDatabases, $collectDatabase );
        $dbNameToDBInfo->{ $database->{NAME} } = $collectDatabase;

        my $instances = $database->{INSTANCES};
        foreach my $instance (@$instances) {
            my $collectInstance = {};
            map { $collectInstance->{$_} = $instance->{$_} } keys(%$instance);
            $collectInstance->{PROC_INFO} = {
                PID  => $collectDatabase->{PROC_INFO}->{PID},
                PPID => $collectDatabase->{PROC_INFO}->{PPID}
            };
            $collectInstance->{NOT_PROCESS}            = 1;
            $collectInstance->{RUN_ON}                 = [];
            $instanceMap->{ $collectInstance->{NAME} } = $collectInstance;
        }
    }
    my @collectInstances = values(%$instanceMap);

    push( @collectSet, @collectDatabases );
    push( @collectSet, @collectInstances );

    return @collectSet;
}

sub getGridProc {
    my ($self) = @_;

    my $procInfo;
    my $pFinder = $self->{pFinder};

    #64936 grid     /u01/app/grid/product/19.0.0/gridhome_1/bin/ocssd.bin
    my $pid;
    my $gridPsLines = $self->getCmdOutLines('ps -eo pid,args |grep /bin/ocssd.bin');
    foreach my $line (@$gridPsLines) {
        if ( $line !~ /grep/ and $line =~ /^\s*(\d+)/ ) {
            $pid = $1;
            last;
        }
    }
    if ( defined($pid) ) {
        $procInfo = $pFinder->getProcess($pid);
    }

    return $procInfo;
}

sub getTnsListenerBackLog {
    my ($self) = @_;

    my $procInfo;
    my $pFinder    = $self->{pFinder};
    my $connGather = $pFinder->{connGather};

    #15908 /u01/app/19.3.0/grid/bin/tnslsnr ASMNET1LSNR_ASM -no_crs_notify -inherit
    my $lsnrPortsMap = {};
    my $gridPsLines  = $self->getCmdOutLines('ps -eo pid,args |grep /bin/tnslsnr');
    foreach my $line (@$gridPsLines) {
        if ( $line !~ /grep/ and $line =~ /^\s*(\d+)/ ) {
            my $pid      = $1;
            my $portsMap = $connGather->getListenPorts($pid);
            map { $lsnrPortsMap->{$_} = $portsMap->{$_} } ( keys(%$portsMap) );
        }
    }

    return $lsnrPortsMap;
}

sub collect {
    my ($self) = @_;
    $self->{isVerbose} = 1;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        print("WARN: It is not oracle main process.\n");
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $envMap   = $procInfo->{ENVIRONMENT};
    my $osUser   = $procInfo->{USER};
    my $oraSid;

    my $comm    = $procInfo->{COMM};
    my $command = $procInfo->{COMMAND};
    if ( ( $comm eq 'oracle' or $command =~ /^\Q$comm\E/ ) and $command =~ /^ora_pmon_(.*)$/ ) {
        $oraSid = $1;
    }
    else {
        #不是Oracle进程
        print("WARN: It is not oracle pmon process.\n");
        return undef;
    }
    print("INFO: Oracle SID: $oraSid.\n");

    my $tnsLsnrBaclogMap = $self->getTnsListenerBackLog();
    $self->{tnsLsnrBaclogMap} = $tnsLsnrBaclogMap;

    my @collectSet = ();

    #如果当前实例是RAC，则优先采集RAC信息，ORACLE集群信息

    my $racInfo;
    my $gridProcInfo = $self->getGridProc();
    if ( defined($gridProcInfo) ) {
        $racInfo              = {};
        $racInfo->{PROC_INFO} = $gridProcInfo;
        $racInfo->{OS_USER}   = $gridProcInfo->{USER};
        $racInfo->{GRID_USER} = $gridProcInfo->{USER};
        my $racColletSet = $self->collectRAC($racInfo);
        push( @collectSet, @$racColletSet );
    }

    my $insInfo = {};
    $insInfo->{PROC_INFO} = $procInfo;
    if ( defined($racInfo) ) {
        $insInfo->{GRID_HOME} = $racInfo->{ORACLE_HOME};
        $insInfo->{GRID_BASE} = $racInfo->{ORACLE_BASE};
        $insInfo->{GRID_USER} = $racInfo->{GRID_USER};
    }
    else {
        $insInfo->{OS_USER} = $osUser;
    }

    my $insInfo = $self->collectIns($insInfo);
    if ( defined($insInfo) ) {
        if ( defined($racInfo) ) {
            $insInfo->{CLUSTER_NAME} = $racInfo->{CLUSTER_NAME};
        }

        #ORACLE实例信息采集完成
        push( @collectSet, $insInfo );

        my @databases = ();
        my $CDBS      = $self->collectCDB($insInfo);
        if ( defined($CDBS) and scalar(@$CDBS) > 0 ) {
            foreach my $CDB (@$CDBS) {
                push( @collectSet, $CDB );
                push(
                    @databases,
                    {
                        _OBJ_CATEGORY => $CDB->{_OBJ_CATEGORY},
                        _OBJ_TYPE     => $CDB->{_OBJ_TYPE},
                        _APP_TYPE     => $CDB->{_APP_TYPE},
                        NAME          => $CDB->{NAME},
                        PRIMARY_IP    => $CDB->{PRIMARY_IP},
                        PORT          => $CDB->{PORT},
                    }
                );
            }
        }

        #如果当前实例运行在CDB模式下，则采集CDB中的所有PDB
        if ( $insInfo->{IS_CDB} == 1 ) {
            my $PDBS = $self->collectPDB($insInfo);

            if ( defined($PDBS) ) {
                foreach my $PDB (@$PDBS) {
                    push( @collectSet, $PDB );
                    push(
                        @databases,
                        {
                            _OBJ_CATEGORY => $PDB->{_OBJ_CATEGORY},
                            _OBJ_TYPE     => $PDB->{_OBJ_TYPE},
                            _APP_TYPE     => $PDB->{_APP_TYPE},
                            NAME          => $PDB->{NAME},
                            PRIMARY_IP    => $PDB->{PRIMARY_IP},
                            PORT          => $PDB->{PORT},
                        }
                    );
                }
            }
        }
    }

    return @collectSet;
}

1;
