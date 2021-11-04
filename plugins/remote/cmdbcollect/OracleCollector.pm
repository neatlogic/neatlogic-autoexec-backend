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

sub getPK {
    my ($self) = @_;
    return { 'Oracle-RAC' => ['UNIQUE_NAME'] };
}

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

sub getGridHome {
    my ($self) = @_;

    my $gridBase;
    my $gridHome;

    if ( not defined($gridHome) ) {
        my $gridHomeDefLines;
        if ( $self->{isRoot} ) {
            $gridHomeDefLines = $self->getCmdOutLines( 'env', $self->{gridUser} );
        }
        else {
            my $homeDir;
            my $homeDirDef = $self->getCmdOut('cat /etc/passwd |grep ^grid:');
            if ( defined($homeDirDef) and $homeDirDef ne '' ) {
                my @items = split( /:/, $homeDirDef );
                $homeDir = $items[-2];
            }
            if ( defined($homeDir) ) {
                $gridHomeDefLines = $self->getCmdOutLines(q{cat "$homeDir/.profile" "$homeDir/.bash_profile" 2>&1});
            }
        }

        foreach my $line (@$gridHomeDefLines) {
            if ( $line =~ /ORACLE_HOME=(.*)$/ ) {
                $gridHome = $1;
            }
            elsif ( $line =~ /ORACLE_BASE=(.*)$/ ) {
                $gridBase = $1;
            }
        }
    }

    if ( not defined($gridHome) ) {

        #oracle   1515      1   0   Mar 30 ?         173:36 /u01/app/11.2.0.3/grid/bin/evmd.bin
        my $gridHomeDef = $self->getCmdOut('ps -ef |grep "/grid/bin/" | head -n1');
        if ( $gridHomeDef =~ /\s(.*?\/grid)\/bin\// ) {
            $gridHome = $1;
        }
    }

    if ( not defined($gridHome) ) {
        my $oraTabFile = '/etc/oratab';
        if ( not -e $oraTabFile ) {
            $oraTabFile = '/var/opt/oracle/oratab';
        }
        if ( -e $oraTabFile ) {
            my $fh = IO::File->new( $oraTabFile, 'r' );
            if ( defined($fh) ) {
                my $fSize = -s $oraTabFile;
                my $content;
                $fh->read( $content, $fSize );
                $fh->close();

                #:/u01/app/11.2.0.3/grid:
                if ( $content =~ /:(\/.*?\/grid):/s ) {
                    $gridHome = $1;
                }
            }
        }
    }

    if ( defined($gridHome) and not defined($gridBase) ) {
        $gridBase = dirname( dirname($gridHome) );
        while ( not -d "$gridBase/grid" ) {
            $gridBase = dirname($gridBase);
        }
    }
    if ( not defined($gridBase) ) {
        $gridBase = dirname($gridHome);
    }

    return ( $gridBase, $gridHome );
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
    my ($self) = @_;

    my $version = '';
    my $sqlplus = $self->{sqlplus};

    my $sql = q{select banner VERSION from v$version where rownum <=1;};

    my $rows = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );
    if ( defined($rows) ) {
        $version = $$rows[0]->{VERSION};
    }
    if ( defined($version) and $version =~ /\s([\d\.]+)\s/ ) {
        $version = $1;
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

    my $tableSpaces = {};

    my $sql = q{
        SELECT df.tablespace_name                    "NAME",
            totalusedspace                        "USED_MB",
            ( df.totalspace - tu.totalusedspace ) "FREE_MB",
            df.totalspace                         "TOTAL_MB",
            Round(100 * ( tu.totalusedspace / df.totalspace )) "PCT_USE"
        FROM   (SELECT tablespace_name,
                    Round(SUM(bytes) / ( 1024 * 1024 )) TotalSpace
                FROM   dba_data_files
                GROUP  BY tablespace_name) df,
            (SELECT Round(SUM(bytes) / ( 1024 * 1024 )) totalusedspace,
                    tablespace_name
                FROM   dba_segments
                GROUP  BY tablespace_name) tu
        WHERE  df.tablespace_name = tu.tablespace_name;
    };
    if ( defined($pdbName) and $pdbName ne '' ) {
        $sql = "alter session set container=$pdbName;\n$sql";
    }
    my $rows = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );
    foreach my $row (@$rows) {
        my $tableSpaceName = $row->{NAME};

        my $tableSpaceInfo = {};
        $tableSpaceInfo->{TABLESPACE_NAME} = $tableSpaceName;
        $tableSpaceInfo->{TOTAL_GB}        = $row->{TOTAL_MB} / 1024;
        $tableSpaceInfo->{USED_GB}         = $row->{USED_MB} / 1024;
        $tableSpaceInfo->{FREE_GB}         = $row->{FREE_MB} / 1024;
        $tableSpaceInfo->{'USED%'}         = $row->{PCT_USE} + 0.0;

        $tableSpaces->{$tableSpaceName} = $tableSpaceInfo;
    }

    $sql = q{select tablespace_name, file_name, round(bytes/1024/1024/1024, 2) GIGA, autoextensible AUTOEX from dba_data_files};
    if ( defined($pdbName) and $pdbName ne '' ) {
        $sql = "alter session set container=$pdbName;\n$sql";
    }

    $rows = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );
    foreach my $row (@$rows) {
        my $dataFileInfo   = {};
        my $tableSpaceName = $row->{TABLESPACE_NAME};

        $dataFileInfo->{FILE_NAME}      = $row->{FILE_NAME};
        $dataFileInfo->{SIZE}           = $row->{GIGA} + 0.0;
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

    my $procInfo = $self->{procInfo};
    my $osUser   = $procInfo->{USER};

    my $gridHome;
    my $gridBase;
    my $sqlplus   = $self->{sqlplus};
    my $isVerbose = $self->{isVerbose};

    my $version = $self->getVersion();
    $insInfo->{VERSION} = $version;

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

        #如果是集群增加两个属性
        #TODO：确认gird版本的oracle的pmon进程身份是否是grid
        ( $gridBase, $gridHome ) = $self->getGridHome();
        $insInfo->{GRID_BASE} = $gridBase;
        $insInfo->{GRID_HOME} = $gridHome;
        $self->{srvctlPath}   = File::Spec->canonpath("$gridHome/bin/srvctl");
    }
    $insInfo->{IS_RAC} = $isRAC;

    $insInfo->{SGA_MAX_SIZE}     = $param->{sga_max_size};
    $insInfo->{MEMORY_TARGET}    = $param->{memory_target};
    $insInfo->{LOG_ARCHIVE_DEST} = $param->{log_archive_dest_1};
    if ( not defined( $insInfo->{LOG_ARCHIVE_DEST} ) ) {
        $insInfo->{LOG_ARCHIVE_DEST} = $param->{log_archive_dest};
    }

    my $svcNameMap      = {};
    my $serviceNamesTxt = $param->{service_names};
    foreach my $oneSvcName ( split( /,/, $serviceNamesTxt ) ) {
        if ( not defined( $insInfo->{SERVICE_NAME} ) ) {
            $insInfo->{SERVICE_NAME} = $oneSvcName;
        }
        $svcNameMap->{$oneSvcName} = 1;
    }
    $rows = $sqlplus->query(
        sql     => q{select a.name from dba_services a,v$database b where b.DATABASE_ROLE='PRIMARY' and a.name not like 'SYS%'},
        verbose => $isVerbose
    );

    foreach my $row (@$rows) {
        if ( not defined( $insInfo->{SERVICE_NAME} ) ) {
            $insInfo->{SERVICE_NAME} = $row->{NAME};
        }
        $svcNameMap->{ $row->{NAME} } = 1;
    }
    my @serviceNames = ();
    foreach my $svcName ( keys(%$svcNameMap) ) {
        push( @serviceNames, { NAME => $svcName } );
    }
    $insInfo->{SERVICE_NAMES} = \@serviceNames;

    $rows = $sqlplus->query(
        sql     => q{select PARAMETER,VALUE from nls_database_parameters where PARAMETER='NLS_CHARACTERSET'},
        verbose => $isVerbose
    );
    if ( defined($rows) ) {
        $insInfo->{NLS_CHARACTERSET} = $$rows[0]->{VALUE};
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
        $diskGroup->{TOTAL_MB} = $row->{TOTAL_MB} + 0.0;
        $diskGroup->{FREE_MB}  = $row->{FREE_MB} + 0.0;
        $diskGroup->{USED_MB}  = 0.0 + $row->{TOTAL_MB} - $row->{FREE_MB};
        $diskGroup->{'USED%'} = sprintf( '.2f%', ( $row->{TOTAL_MB} - $row->{FREE_MB} ) * 100 / $row->{TOTAL_MB} ) + 0.0;
        $diskGroup->{DISKS} = [];
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
        $disk->{TOTAL_MB}     = $row->{TOTAL_MB} + 0.0;
        $disk->{FREE_MB}      = $row->{FREE_MB} + 0.0;
        $disk->{USED_MB}      = 0.0 + $row->{TOTAL_MB} - $row->{FREE_MB};
        $disk->{'USED%'} = sprintf( '.2f%', ( $row->{TOTAL_MB} - $row->{FREE_MB} ) * 100 / $row->{TOTAL_MB} ) + 0.0;
        $disk->{PATH} = $row->{PATH};

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
    $insInfo->{_OBJ_TYPE}   = $procInfo->{_OBJ_TYPE};

    my ( $port, $listenAddrs, $servicesMap ) = $self->getListenerInfo($insInfo);
    $insInfo->{PORT} = $port;
    my @serviceNames = keys(%$servicesMap);
    $insInfo->{LISTEN_ADDRS} = $listenAddrs;
    $insInfo->{SERVICE_INFO} = $servicesMap;
    $insInfo->{SERVER_NAME}  = $serviceNames[0];

    if ($isRAC) {
        my $clusterName = $self->getClusterName($insInfo);
        $insInfo->{CLUSTER_NAME} = $clusterName;
        my $nodeVip = $self->getLocalNodeVip($insInfo);
        $insInfo->{NODE_VIP} = $nodeVip;
    }

    return $insInfo;
}

sub getClusterDBNames {
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    # $ srvctl config database
    # orcl1
    # orcl2
    my $dbNamesLines = $self->getCmdOutLines( "$gridBin/srvctl config database", $self->{gridUser} );
    my @dbNames;
    foreach my $dbName (@$dbNamesLines) {
        $dbName =~ s/^\s*|\*$//g;
        if ( $dbName ne '' ) {
            push( @dbNames, $dbName );
        }
    }
    return \@dbNames;
}

sub getClusterVersion {
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    my $version;

    # $ crsctl query crs activeversion -f
    # Oracle Clusterware active version on the cluster is [12.1.0.0.2]. The cluster
    # upgrade state is [NORMAL]. The cluster active patch level is [456789126].
    my $verDef = $self->getCmdOut( "$gridBin/crsctl query crs activeversion -f", $self->{gridUser} );
    if ( $verDef =~ /\[[\d\.]+\]/s ) {
        $version = $1;
    }
    return $version;
}

sub getClusterName {
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    # [root@rac1 bin]# ./cemutlo -n
    # crs
    my $clusterName = $self->getCmdOut( "$gridBin/cemutlo -n", $self->{gridUser} );
    $clusterName =~ s/^\s*|\s*$//g;
    return $clusterName;
}

sub getClusterLocalNode {
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    #olsnodes -l #get local node
    my $node = $self->getCmdOut( "$gridBin/olsnodes -l", $self->{gridUser} );
    $node =~ s/^\s*|\s*$//g;
    return $node;
}

sub getClusterNodes {
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    # [root@node1]# olsnodes
    # node1
    # node2
    # node3
    # node4
    my $dbNodesLines = $self->getCmdOutLines( "$gridBin/olsnodes", $self->{gridUser} );
    my @dbNodes;
    foreach my $dbNode (@$dbNodesLines) {
        $dbNode =~ s/^\s*|\*$//g;
        if ( $dbNode ne '' ) {
            push( @dbNodes, $dbNode );
        }
    }

    return \@dbNodes;
}

sub getScanInfo {
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    my $scanInfo = {};
    my @scanIps  = ();

    # [grid@rac2 ~]$ srvctl config scan
    # SCAN name: racnode-cluster-scan.racnode.com, Network: 1/192.168.3.0/255.255.255.0/eth0
    # SCAN VIP name: scan1, IP: /racnode-cluster-scan.racnode.com/192.168.3.231
    # SCAN VIP name: scan2, IP: /racnode-cluster-scan.racnode.com/192.168.3.233
    # SCAN VIP name: scan3, IP: /racnode-cluster-scan.racnode.com/192.168.3.232
    my $scanInfoLines = $self->getCmdOutLines( "$gridBin/srvctl config scan", $self->{gridUser} );
    foreach my $line (@$scanInfoLines) {
        if ( $line =~ /^SCAN name:\s*(.*?),\s*Network:.*?\/(.*?)\/(.*?)\/(.*?)$/ ) {
            $scanInfo->{NAME}    = $1;
            $scanInfo->{NET}     = $2;
            $scanInfo->{NETMASK} = $3;
            $scanInfo->{NIC}     = $4;
        }
        elsif ( $line =~ /VIP.*?(\d+\.\d+\.\d+\.\d+)/ ) {
            push( @scanIps, $1 );
        }
    }
    $scanInfo->{VIPS} = \@scanIps;

    return $scanInfo;
}

sub getLocalNodeVip {
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    my $nodeVip;
    my $localNode = $self->getClusterLocalNode($insInfo);

    # [oracle@node-rac1 ~]$ srvctl config nodeapps -n node-rac2
    # VIP exists.: /node-vip2/192.168.12.240/255.255.255.0/eth0
    # GSD exists.
    my $nodeVipInfoLines = $self->getCmdOutLines( "$gridBin/srvctl config nodeapps -n $localNode", $self->{gridUser} );
    foreach my $line (@$nodeVipInfoLines) {
        if ( $line =~ qr{/.*?/(.*?)/.*?/.*?/.*?, hosting node (.*)} ) {
            $nodeVip = $1;
        }
        elsif ( $line =~ qr{VIP exists\.:\s*/.*?/(.*?)/.*?/.*?} ) {
            $nodeVip = $1;
        }
    }

    return $nodeVip;
}

sub getNodeVipInfo {
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    # [oracle@node-rac1 ~]$ srvctl config nodeapps -n node-rac2
    # VIP exists.: /node-vip2/192.168.12.240/255.255.255.0/eth0
    # GSD exists.
    # ONS daemon exists.
    # Listener exists.
    my @nodeVips = ();
    my $nodeVipInfoLines = $self->getCmdOutLines( "$gridBin/srvctl config nodeapps -a", $self->{gridUser} );
    foreach my $line (@$nodeVipInfoLines) {
        if ( $line =~ qr{/(.*?)/(.*?)/(.*?)/(.*?)/(.*?), hosting node (.*)$} ) {
            my $nodeVipInfo = {};
            $nodeVipInfo->{NAME}    = $1;
            $nodeVipInfo->{IP}      = $2;
            $nodeVipInfo->{NETMASK} = $4;
            $nodeVipInfo->{NIC}     = $5;
            $nodeVipInfo->{NODE}    = $6;
            push( @nodeVips, $nodeVipInfo );
        }
        elsif ( $line =~ qr{VIP exists\.:\s*/(.*?)/(.*?)/(.*?)/(.*?)$} ) {
            my $nodeVipInfo = {};
            $nodeVipInfo->{NAME}    = $1;
            $nodeVipInfo->{IP}      = $2;
            $nodeVipInfo->{NETMASK} = $3;
            $nodeVipInfo->{NIC}     = $4;
            $nodeVipInfo->{NODE}    = ( split( /-/, $nodeVipInfo->{NAME} ) )[0];
            push( @nodeVips, $nodeVipInfo );
        }
    }

    return \@nodeVips;
}

sub getIpInHostsByHostName {
    my ( $self, $hostName ) = @_;

    my @ips = ();
    my $fh  = IO::File->new('/etc/hosts');
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            if ( $line =~ /\b($hostName)\b/ and $line !~ /^\s*#/ ) {
                if ( $hostName eq $1 ) {
                    my $ip = ( split( /\s+/, $line ) )[0];
                    if ( $ip ne '127.0.0.1' and $ip ne '0.0.0.0' ) {
                        push( @ips, $ip );
                    }
                }
            }
        }

        $fh->close();
    }

    return @ips;
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
    my ( $self, $outLines ) = @_;

    my $miniPort    = 65536;
    my @listenAddrs = ();
    my @services    = ();
    my $servicesMap = ();
    for ( my $i = 0 ; $i < scalar(@$outLines) ; $i++ ) {
        my $line = $$outLines[$i];

        # Listening Endpoints Summary...
        if ( $line =~ /^Listening Endpoints Summary\.\.\./ ) {
            $i++;
            $line = $$outLines[$i];

            #   (DESCRIPTION=(ADDRESS=(PROTOCOL=ipc)(KEY=LISTENER_SCAN2)))
            while ( $line =~ /^\s*\(DESCRIPTION=\(ADDRESS=\(PROTOCOL=/ ) {
                if ( $line =~ /\(HOST=(.*?)\)\(PORT=(\d+)\)/ ) {
                    my $listenInfo = {};
                    my $host       = $1;
                    my $port       = int($2);

                    #TODO；getbyhostname调用其实是会返回多个IP的，譬如：一个域名对应多个IP
                    my $ipAddr = gethostbyname($host);
                    $listenInfo->{IP}   = inet_ntoa($ipAddr);
                    $listenInfo->{PORT} = $port;
                    if ( $port < $miniPort ) {
                        $miniPort = $port;
                    }
                    push( @listenAddrs, $listenInfo );
                }
                $i++;
                $line = $$outLines[$i];
            }
            $i--;
        }

        # Service "grac4" has 3 instance(s).
        elsif ( $line =~ /^Service "(.*?)" has \d+ instance\(s\)\./ ) {
            my $serviceName = $1;
            $i++;
            $line = $$outLines[$i];

            my @serviceInstances = ();

            #   Instance "grac41", status READY, has 1 handler(s) for this service...
            while ( $line =~ /Instance "(.*?)", status (\w+), has \d+ handler\(s\) for this service\.\.\./ ) {
                my $insName   = $1;
                my $insStatus = $2;
                my $insMap    = {};
                $insMap->{NAME}   = $insName;
                $insMap->{STATUS} = $insStatus;

                push( @serviceInstances, $insMap );
                $i++;
                $line = $$outLines[$i];
            }
            $i--;

            my $serviceInfo = {};
            $serviceInfo->{NAME}      = $serviceName;
            $serviceInfo->{INSTANCES} = \@serviceInstances;

            $servicesMap->{$serviceName} = $serviceInfo;
        }
    }

    if ( $miniPort < 65536 ) {
        $miniPort = 0;
    }

    return ( $miniPort, \@listenAddrs, $servicesMap );
}

sub getListenerInfo {
    my ( $self, $insInfo ) = @_;
    my $oraHome = $insInfo->{ORACLE_HOME};
    my $osUser  = $self->{oracleUser};

    my $outLines = $self->getCmdOutLines( "LANG=en_US.UTF-8 $oraHome/bin/lsnrctl status", $osUser );
    return $self->parseListenerInfo($outLines);
}

sub getGridListenerInfo {
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridUser = $self->{gridUser};

    # srvctl status  scan_listener
    # $ srvctl status  scan_listener
    # SCAN Listener LISTENER_SCAN1 is enabled
    # SCAN listener LISTENER_SCAN1 is running on node grac2
    # SCAN Listener LISTENER_SCAN2 is enabled
    # SCAN listener LISTENER_SCAN2 is running on node grac1
    # SCAN Listener LISTENER_SCAN3 is enabled
    # SCAN listener LISTENER_SCAN3 is running on node grac1

    #获取其中一个Listener，通过lsnrctl获取service names信息
    my ( $listener, $enableListener, $activeListener );
    my $scanStatusLines = $self->getCmdOutLines( "LANG=en_US.UTF-8 $gridHome/bin/srvctl status scan_listener", $gridUser );
    foreach my $line (@$scanStatusLines) {
        if ( $line =~ /^SCAN listener (.*?) is running/ ) {
            $activeListener = $1;
        }
        elsif ( $line =~ /^SCAN Listener (.*?) is enabled/ ) {
            $enableListener = $1;
        }
    }

    if ( defined($activeListener) ) {
        $listener = $activeListener;
    }
    else {
        $listener = $enableListener;
    }

    my $outLines = $self->getCmdOutLines( "LANG=en_US.UTF-8 $gridHome/bin/lsnrctl status $listener", $gridUser );
    return $self->parseListenerInfo($outLines);
}

sub collectPDBS {
    my ( $self, $insInfo ) = @_;

    #获取所有的PDB信息
    my @pdbs    = ();
    my $sqlplus = $self->{sqlplus};
    my $sql     = q{select name,dbid,con_id from v$pdbs where name<>'PDB$SEED'};
    my $rows    = $sqlplus->query(
        sql     => $sql,
        verbose => $self->{isVerbose}
    );
    foreach my $row (@$rows) {
        my $pdb = {};
        $pdb->{NAME}   = $row->{NAME};
        $pdb->{DBID}   = $row->{DBID};
        $pdb->{CON_ID} = $row->{CON_ID};
        push( @pdbs, $pdb );
    }

    #获取PDB的service names
    foreach my $pdb (@pdbs) {
        my $pdbName = $pdb->{NAME};
        my $sql     = qq{alter session set container=$pdbName;\nselect name from dba_services where name not like 'SYS%';};
        my $rows    = $sqlplus->query(
            sql     => $sql,
            verbose => $self->{isVerbose}
        );
        my @serviceNames = ();
        foreach my $row (@$rows) {
            push( @serviceNames, $row->{NAME} );
        }
        $pdb->{SERVICE_NAMES}  = \@serviceNames;
        $pdb->{SERVICE_NAME}   = $serviceNames[0];
        $pdb->{USERS}          = $self->getUserInfo($pdbName);
        $pdb->{TABLE_SPACESES} = $self->getTableSpaceInfo($pdbName);

        #TODO: 需要补充当前PDB的IP信息，RAC和非RAC
        #TODO: 根据模型设置是否需要全盘拷贝instance信息
        map { $pdb->{$_} = $insInfo->{$_} } keys(%$insInfo);

        #$pdb->{_OBJ_TYPE} = 'Oracle-PDB';
    }

    return \@pdbs;
}

sub collectRAC {
    my ( $self, $insInfo ) = @_;
    my ( $self, $insInfo ) = @_;
    my $gridHome = $insInfo->{GRID_HOME};
    my $gridBin  = "$gridHome/bin";

    my $racInfo = {};

    my $localNode = $self->getClusterLocalNode($insInfo);
    if ( not defined($localNode) ) {
        return undef;
    }

    my $clusterNodes = $self->getClusterNodes($insInfo);

    #把$insInfo的信息复制过来
    map { $racInfo->{$_} = $insInfo->{$_} } keys(%$insInfo);
    $racInfo->{_OBJ_CATEGORY} = CollectObjCat->get('CLUSTER');
    $racInfo->{_OBJ_TYPE}     = 'Oracle-RAC';

    my $version = $self->getClusterVersion($insInfo);
    $insInfo->{CLUSTER_VERSION} = $version;

    my $dbNames = $self->getClusterDBNames($insInfo);

    my @nodeAddrs = ();
    my @dbInfos   = ();
    foreach my $dbName (@$dbNames) {
        my $dbInfo = {};

        #Instance ASKMDB1 is not running on node exaaskmdb01
        #Instance ASKMDB2 is running on node exaaskmdb02
        my $nodeToInsMap = {};
        my ( $status, $outLines ) = $self->getCmdOutLines( "$gridBin/srvctl status database -d '$dbName' -f", $self->{gridUser} );
        if ( $status == 0 and defined($outLines) ) {
            foreach my $line (@$outLines) {
                if ( $line =~ /Instance\s+(.*)\s+is\s+.*?running\s+on\s+node\s+(.*)$/ ) {
                    my $instanceName = $1;
                    my $nodeName     = $2;
                    $nodeToInsMap->{$nodeName} = $instanceName;
                }
            }

            my $sid = $1;
            my ( $oraHome, $oraUser );
            my $infoLines = $self->getCmdOutLines("$gridBin/srvctl config database -d '$dbName'");
            foreach my $line (@$infoLines) {
                if ( $line =~ /oracle home:\s*(.*)$/i ) {
                    $oraHome = $1;
                }
                elsif ( $line =~ /oracle user:\s*(.*)$/i ) {
                    $oraUser = $1;
                }
            }

            if ( defined($oraHome) or defined($oraUser) ) {
                my @nodes = ();
                foreach my $node (@$clusterNodes) {
                    my $instanceName = $nodeToInsMap->{$node};
                    if ( defined($instanceName) ) {
                        my $nodeInfo = {};
                        $nodeInfo->{NAME}          = $node;
                        $nodeInfo->{INSTANCE_NAME} = $instanceName;

                        #TODO；getbyhostname调用其实是会返回多个IP的，譬如：一个域名对应多个IP
                        my $nodeAddr = gethostbyname($node);
                        my $nodeIp;
                        if ( defined($nodeAddr) ) {
                            $nodeIp = inet_ntoa($nodeAddr);
                        }
                        else {
                            $nodeIp = $self->getIpInHostsByHostName($node);
                        }
                        if ( $nodeIp ne '0.0.0.0' and $nodeIp ne '127.0.0.1' ) {
                            $nodeInfo->{IP} = $nodeIp;
                        }
                        push( @nodeAddrs, "$nodeIp/$instanceName" );
                        push( @nodes,     $nodeInfo );
                    }
                }

                #TODO: listener 中service name如何跟库发生联系？？
                my ( $port, $listenAddrs, $servicesMap ) = $self->getListenerInfo($insInfo);
                my @serviceNames = keys(%$servicesMap);
                $dbInfo->{LISTEN_ADDRS} = $listenAddrs;
                my @serviceInfos = values(%$servicesMap);
                $dbInfo->{SERVICE_INFOS} = \@serviceInfos;

                my $dbInfo = {};
                $dbInfo->{NAME}          = $dbName;
                $dbInfo->{NODES}         = \@nodes;
                $dbInfo->{SERVICE_NAMES} = \@serviceNames;

                push( @dbInfos, $dbInfo );
            }
        }
    }
    my @sortNodeAddrs = sort(@nodeAddrs);
    my $uniqueName = join( ',', @sortNodeAddrs );
    $racInfo->{UNIQUE_NAME} = $uniqueName;
    $racInfo->{RAC_MEMBERS} = \@dbInfos;
}

sub collect {
    my ($self) = @_;
    $self->{gridUser}  = 'grid';
    $self->{isVerbose} = 1;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $insInfo = {};
    $insInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DB');

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
    $insInfo->{INSTALL_PATH}    = $oraBase;
    $insInfo->{CONFIG_PATH}     = $oraHome;

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
        my $PDBS = $self->collectPDBS($insInfo);

        #if ( defined($PDBS) ) {
        #    push( @collectSet, @$PDBS );
        #}
        $insInfo->{PDBS} = $PDBS;
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
