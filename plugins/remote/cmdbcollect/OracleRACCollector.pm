#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package OracleRACCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use Socket;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use SqlplusExec;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        enabled  => 0,
        regExps  => ['\/bin\/ocssd.bin'],       #正则表达是匹配ps输出
                                                #psAttrs  => { COMM => 'oracle' },       #ps的属性的精确匹配
        envAttrs => { ORACLE_HOME => undef }    #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
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
    $rows = $sqlplus->query(
        sql     => q{select ad.name, adk.name gname, ad.failgroup fgroup, ad.mount_status mnt_sts, ad.total_mb, ad.free_mb, ad.path from v$asm_disk ad,v$asm_diskgroup adk where ad.GROUP_NUMBER=adk.GROUP_NUMBER order by path},
        verbose => $isVerbose
    );
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
                $listenMap->{$lsnAddr} = 1;
                push( @listenAddrs, $lsnAddr );
            }
            foreach my $lsnAddr (@scanAddrs) {
                $listenMap->{$lsnAddr} = 1;
                push( @listenAddrs, $lsnAddr );
            }
        }
        if ( $miniPort == 65535 ) {
            print("WARN: Can not find listen port for db:$dbName.\n");
            next;
        }

        $dbInfo->{PORT}         = $miniPort;
        $dbInfo->{LISTEN_ADDRS} = \@listenAddrs;
        $dbInfo->{LISTEN_MAP}   = $listenMap;

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
                            _OBJ_CATEGORY => CollectObjCat->get('DBINS'),
                            _OBJ_TYPE     => 'Oracle',
                            NAME          => $instanceName,
                            INSTANCE_NAME => $instanceName,
                            NODE_NAME     => $nodeName,
                            MGMT_IP       => $nodeInfo->{IP},
                            VIP           => $nodeInfo->{VIP},
                            PORT          => $miniPort,
                            SERVICE_ADDR  => $nodeInfo->{IP} . ':' . $miniPort,
                            RAC_CLUSTER   => [
                                _OBJ_CATEGORY => CollectObjCat->get('CLUSTER'),
                                _OBJ_TYPE     => 'DBCluster',
                                _APP_TYPE     => 'Oracle',
                                UNIQUE_NAME   => $racInfo->{UNIQUE_NAME},
                                NAME          => $racInfo->{NAME}
                            ]
                        }
                    );
                }
            }

            $dbInfo->{INSTANCES} = \@instances;

            my @svcIps      = ();
            my @insSvcAddrs = ();
            if ( not defined($tnsAddrs) ) {
                my @insAddrs = ();
                foreach my $insInfo (@instances) {
                    if ( defined( $insInfo->{VIP} ) ) {
                        $allIpMap->{ $insInfo->{VIP} } = 1;
                        push( @svcIps,      $insInfo->{VIP} );
                        push( @insSvcAddrs, $insInfo->{VIP} . ':' . $insInfo->{PORT} );
                    }
                    elsif ( defined( $insInfo->{IP} ) ) {
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
                elsif ( scalar(@svcIps) ) {
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

                $tnsAddrs = join( ',', sort(@insSvcAddrs) );
                $dbInfo->{SERVICE_ADDR} = $tnsAddrs;
            }

            delete( $allIpMap->{ $dbInfo->{PRIMARY_IP} } );
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

    $racInfo->{NODES} = \@dbNodes;
    my $primaryIp = $nodePubIps[0];
    $racInfo->{PRIMARY_IP}  = $primaryIp;
    $racInfo->{PORT}        = undef;
    $racInfo->{UNIQUE_NAME} = 'RAC:' . $racInfo->{CLUSTER_NAME} . ':' . $primaryIp;
    $racInfo->{SLAVE_IPS}   = \@nodePubIps;

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

    my ( $status, $nodeVipInfoLines ) = $self->getCmdOutLines( "$gridBin/srvctl config vip -node $nodeName", $self->{gridUser} );
    if ( $status == 0 ) {

        # RAC 12 ############################
        #$ srvctl config vip -node edbassb1p
        # VIP exists: network number 1, hosting node edbassb1p
        # VIP Name: edbassb1p-vip
        # VIP IPv4 Address: 10.0.13.122
        # VIP IPv6 Address:
        # VIP is enabled.
        # VIP is individually enabled on nodes:
        # VIP is individually disabled on nodes:
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
    }
    else {
        #Oracle Rac 11
        #$ tagentexec /u01/app/11.2.0/grid/bin/srvctl config vip -n tyzfdb3p
        #VIP exists: /tyzfdb3p-vip/10.0.12.172/10.0.12.0/255.255.255.0/en6, hosting node tyzfdb3p
        ( $status, $nodeVipInfoLines ) = $self->getCmdOutLines( "$gridBin/srvctl config vip -n $nodeName", $self->{gridUser} );
        foreach my $line (@$nodeVipInfoLines) {
            if ( $line =~ /^\s*VIP exists:\s+\/([^\/]+)\/([\d\.]+)\// ) {
                $vipName = $1;
                $nodeVip = $2;
            }
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
                            foreach my $ipAddr ( gethostbyname($host) ) {
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
    $lsnrInfo->{LISTEN_MAP}    = $lsnPortsMap;

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
        my $lsnrPortsMap = delete( $lsnrInfo->{LISTEN_MAP} );
        push( @listeners, $lsnrInfo );

        my $procInfo = $racInfo->{PROC_INFO};
        my $portsMap = $procInfo->{CONN_INFO}->{LISTEN};
        map { $portsMap->{$_} = $lsnrPortsMap->{$_} } keys(%$lsnrPortsMap);
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
    my ( $listener, $enableListener, $activeListener );
    my $scanStatusLines = $self->getCmdOutLines( "LANG=en_US.UTF-8 $gridHome/bin/srvctl status listener", $osUser );
    foreach my $line (@$scanStatusLines) {
        if ( $line =~ /^Listener (.*?) is running/i ) {
            $activeListener = $1;
            $lsnrNamesMap->{$activeListener} = 1;
        }
        elsif ( $line =~ /^Listener (.*?) is enabled/i ) {
            $enableListener = $1;
            $lsnrNamesMap->{$enableListener} = 1;
        }
    }
    my @lsnrNames = keys(%$lsnrNamesMap);

    my $serviceNameToLsnrMap = {};
    my $insNameToLsnrMap     = {};
    my @listeners            = ();
    foreach my $lsnrName (@lsnrNames) {
        my $outLines = $self->getCmdOutLines( "LANG=en_US.UTF-8 $gridHome/bin/lsnrctl status $lsnrName", $osUser );
        my $lsnrInfo = $self->parseListenerInfo( $outLines, $lsnrName, $serviceNameToLsnrMap, $insNameToLsnrMap );
        if ( not defined($lsnrInfo) ) {
            next;
        }
        delete( $lsnrInfo->{LISTEN_MAP} );
        push( @listeners, $lsnrInfo );
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

    $self->getClusterName($racInfo);

    my $dbNodesMap = $self->getClusterNodes($racInfo);
    my $localNode  = $self->getClusterLocalNode($racInfo);

    my $nodes = $racInfo->{NODES};
    if ( $$nodes[0]->{NAME} ne $localNode ) {
        print("WARN: Rac node:$localNode is not primary node, no need to collect.\n");
        return undef;
    }

    $self->getGridVersion($racInfo);
    $self->getClusterActiveVersion($racInfo);
    $self->getScanInfo($racInfo);
    $self->getASMDiskGroup($racInfo);

    my $svcNameToScanLsnrMap = $self->getScanListenerInfo($racInfo);
    my $svcNameToLsnrMap     = $self->getListenerInfo($racInfo);
    $racInfo->{DATABASES} = $self->getClusterDB( $racInfo, $dbNodesMap, $svcNameToScanLsnrMap, $svcNameToLsnrMap );

    my @collectSet = ();
    push( @collectSet, $racInfo );

    my @collectDatabases = ();
    my $databases        = $racInfo->{DATABASES};
    my $instanceMap      = {};
    foreach my $database (@$databases) {
        my $collectDatabase = {};
        map { $collectDatabase->{$_} = $database->{$_} } keys(%$database);
        delete( $database->{LISTEN_MAP} );
        $collectDatabase->{NOT_PROCESS} = 1;
        $collectDatabase->{RUN_ON}      = [];
        $collectDatabase->{PROC_INFO}   = {
            CONN_INFO => {
                LISTEN => delete( $collectDatabase->{LISTEN_MAP} ),
                PEER   => {}
            }
        };

        push( @collectDatabases, $collectDatabase );

        my $instances = $database->{INSTANCES};
        foreach my $instance (@$instances) {
            my $collectInstance = {};
            map { $collectInstance->{$_} = $instance->{$_} } keys(%$instance);
            $collectInstance->{NOT_PROCESS}            = 1;
            $collectInstance->{RUN_ON}                 = [];
            $instanceMap->{ $collectInstance->{NAME} } = $collectInstance;
        }
    }
    my @collectInstances = values(%$instanceMap);

    push( @collectSet, @collectDatabases );
    push( @collectSet, @collectInstances );

    return \@collectSet;
}

sub collect {
    my ($self) = @_;

    my $racInfo = {};
    $racInfo->{PROC_INFO} = $self->{procInfo};
    my $collectSet = $self->collectRAC($racInfo);

    return @$collectSet;
}

1;
