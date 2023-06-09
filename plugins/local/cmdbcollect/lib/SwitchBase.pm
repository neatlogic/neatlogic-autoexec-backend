#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package SwitchBase;

use strict;
use File::Basename;
use JSON;
use Net::SNMP qw(:snmp);
use SnmpHelper;
use Data::Dumper;

use CollectUtils;

my $BRANDS = [ 'Huawei', 'Cisco', 'H3C', 'HillStone', 'Juniper', 'Ruijie' ];

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    $self->{brand} = $args{brand};
    $self->{DATA}  = { PK => ['MGMT_IP'] };
    bless( $self, $class );

    my $utils = CollectUtils->new();
    $self->{utils} = $utils;

    $self->{snmpHelper} = SnmpHelper->new();

    my $version = $args{version};
    if ( not defined($version) or $version eq '' ) {
        $version = 'snmpv2';
        $args{version} = $version;
    }
    if ( not defined( $args{retries} ) ) {
        $args{retries} = 2;
    }

    my $inspect = $args{inspect};
    if ( not defined($inspect) ) {
        $inspect = 0;
    }

    $self->{inspect} = $inspect;

    my $options = {};
    foreach my $key ( keys(%args) ) {
        if ( $key ne 'node' and $key ne 'brand' and $key ne 'inspect' ) {
            $options->{"-$key"} = $args{$key};
        }
    }
    $options->{'-maxmsgsize'} = 65535;
    $self->{snmpOptions}      = $options;

    my ( $session, $error ) = Net::SNMP->session(%$options);
    if ( !defined $session ) {
        print("ERROR: Create snmp session to $args{hostname} failed, $error\n");
        exit(-1);
    }

    #单值定义
    my $scalarOidDef = {
        DEV_NAME    => '1.3.6.1.2.1.1.5.0',               #sysName
        UPTIME      => '1.3.6.1.2.1.1.3.0',               #sysUpTime
        VENDOR      => '1.3.6.1.2.1.1.4.0',               #sysContact
        MODEL       => '1.3.6.1.2.1.1.1.0',               #sysDescr
        IOS_INFO    => '1.3.6.1.2.1.1.1.0',               #sysDescr
        SN          => ['1.3.6.1.2.1.47.1.1.1.1.11.1'],
        PORTS_COUNT => '1.3.6.1.2.1.2.1.0'                #ifNumber
    };

    #列表值定义
    my $tableOidDef = {
        IP_ADDRS => {
            IP      => '1.3.6.1.2.1.4.20.1.1',
            NETMASK => '1.3.6.1.2.1.4.20.1.3'
        }

            #PORTS_TABLE_FOR_TEST => { NAME => '1.3.6.1.2.1.2.2.1.2', MAC => '1.3.6.1.2.1.2.2.1.6' }
    };

    #通用列表值定义, 这部分不提供给外部修改
    my $commOidDef = {

        #端口信息
        #PORT_INDEX        => '1.3.6.1.2.1.2.2.1.1',      #ifIndex
        #PORT_NAME         => '1.3.6.1.2.1.2.2.1.2',      #ifDescr
        PORT_INDEX        => '1.3.6.1.2.1.17.1.4.1.2',    #dot1dBasePortIfIndex
        PORT_NAME         => '1.3.6.1.2.1.31.1.1.1.1',    #ifName
        PORT_TYPE         => '1.3.6.1.2.1.2.2.1.3',       #ifType
        PORT_MAC          => '1.3.6.1.2.1.2.2.1.6',       #ifPhysAddress
        PORT_ADMIN_STATUS => '1.3.6.1.2.1.2.2.1.7',       #ifAdminStatus
        PORT_OPER_STATUS  => '1.3.6.1.2.1.2.2.1.8',       #ifOperStatus
        PORT_SPEED        => '1.3.6.1.2.1.2.2.1.5',       #ifSpeed
        PORT_MTU          => '1.3.6.1.2.1.2.2.1.4',       #ifMTU
        PORT_OUT_QLEN     => '1.3.6.1.2.1.2.2.1.21',      #ifOutQLen

        #Counter inspect
        PORT_IN_OCTETS         => '1.3.6.1.2.1.2.2.1.10',    #ifInOctets
        PORT_IN_UCAST_PKTS     => '1.3.6.1.2.1.2.2.1.11',    #ifInUcastPkts
        PORT_IN_NUCAST_PKTS    => '1.3.6.1.2.1.2.2.1.12',    #ifInNUcastPkts
        PORT_IN_DISCARDS       => '1.3.6.1.2.1.2.2.1.13',    #ifInDiscards
        PORT_IN_ERRORS         => '1.3.6.1.2.1.2.2.1.14',    #ifInErrors
        PORT_IN_UNKNOWN_PROTOS => '1.3.6.1.2.1.2.2.1.15',    #ifInUnknownProtos
        PORT_OUT_OCTETS        => '1.3.6.1.2.1.2.2.1.16',    #ifOutOctets
        PORT_OUT_UCAST_PKTS    => '1.3.6.1.2.1.2.2.1.17',    #ifOutUcastPkts
        PORT_OUT_NUCAST_PKTS   => '1.3.6.1.2.1.2.2.1.18',    #ifOutNUcastPkts
        PORT_OUT_DISCARDS      => '1.3.6.1.2.1.2.2.1.19',    #ifOutDiscards
        PORT_OUT_ERRORS        => '1.3.6.1.2.1.2.2.1.20',    #ifOutErrors

        #MAC地址和端口对照表
        CISCO_VLAN_STATE => '1.3.6.1.4.1.9.9.46.1.3.1.1.2',    #vtpVlanState
        MAC_TABLE_PORT   => '1.3.6.1.2.1.17.4.3.1.2',          #dot1qTpFdbPort
        MAC_TABLE_MAC    => '1.3.6.1.2.1.17.4.3.1.1',          #dot1qTpFdbMac

        #交换机邻居表
        LLDP_LOCAL_PORT     => '1.0.8802.1.1.2.1.3.7.1.3',     #lldpLocPortId
        LLDP_REMOTE_PORT    => '1.0.8802.1.1.2.1.4.1.1.7',     #lldpRemPortId
        LLDP_REMOTE_SYSNAME => '1.0.8802.1.1.2.1.4.1.1.9',     #lldpRemSysName

        #Cisco CDP 邻居表
        CDP_REMOTE_SYSNAME => '1.3.6.1.4.1.9.9.23.1.2.1.1.6',    #cdpCacheDeviceId
        CDP_REMOTE_PORT    => '1.3.6.1.4.1.9.9.23.1.2.1.1.7',    #cdpCacheDevicePort
        CDP_TYPE           => '1.3.6.1.4.1.9.9.23.1.2.1.1.3',    #cdpCacheAddressType
        CDP_IP             => '1.3.6.1.4.1.9.9.23.1.2.1.1.4'     #cdpCacheAddress
    };

    $self->{commonOidDef} = $commOidDef;
    $self->{scalarOidDef} = $scalarOidDef;
    $self->{tableOidDef}  = $tableOidDef;

    $self->{snmpSession} = $session;

    END {
        local $?;
        if ( defined($session) ) {
            $session->close();
        }
    }

    return $self;
}

#重载此方法，调整snmp oid的设置
sub before {
    my ($self) = @_;

    #$self->addScalarOid( SN => '1.3.6.1.2.1.47.1.1.1.1.11.1' );
    #$self->addTableOid( PORTS_TABLE_FOR_TEST => [ { NAME => '1.3.6.1.2.1.2.2.1.2' }, { MAC => '1.3.6.1.2.1.2.2.1.6' } ] );
    #$self->setCommonOid( PORT_TYPE => '1.3.6.1.2.1.2.2.1.3' );
}

#重载此方法，进行数据调整，或者补充其他非SNMP数据
sub after {
    my ($self) = @_;

    #my $data = $self->{DATA};
    #my $model = $data->{MODEL};
    #if ( defined($model) ){
    #    my @lines = split(/\n/, $model);
    #    $data->{MODEL} = $lines[0];
    #}
}

#提供给外部调用，通过此方法增加或修改单值OID的设置
#例如：addScalarOid(SN=>'1.3.6.1.4.1.2011.10.2.6.1.2.1.1.2.0', PORTS_COUNT=>'1.3.6.1.2.1.2.1.0');
sub addScalarOid {
    my ( $self, %args ) = @_;
    my $scalarOidDef = $self->{scalarOidDef};

    foreach my $key ( keys(%args) ) {
        $scalarOidDef->{$key} = $args{$key};
    }
}

#提供给外部调用，通过此方法增加或修改列表值OID的设置
#例如：addTableOid(PORTS_TABLE => [ { DESC => '1.3.6.1.2.1.2.2.1.2' }, { MAC => '1.3.6.1.2.1.2.2.1.6' } ]);
sub addTableOid {
    my ( $self, %args ) = @_;
    my $tableOidDef = $self->{tableOidDef};

    foreach my $key ( keys(%args) ) {
        $tableOidDef->{$key} = $args{$key};
    }
}

sub setCommonOid {
    my ( $self, %args ) = @_;
    my $commonOidDef = $self->{commOidDef};

    foreach my $key ( keys(%args) ) {
        $commonOidDef->{$key} = $args{$key};
    }
}

sub _errCheck {
    my ( $self, $queryResult, $oid, $name ) = @_;
    my $hasError = 0;
    my $snmp     = $self->{snmpSession};
    if ( not defined($queryResult) ) {
        $hasError = 1;
        my $error = $snmp->error();
        if ( $error =~ /^No response/i ) {
            print("ERROR: $error, snmp failed, exit.\n");
            exit(-1);
        }
        else {
            if ( ref($oid) eq 'ARRAY' ) {
                print( "WARN: $error, $name oids:", join( ', ', @$oid ), "\n" );
            }
            else {
                print("WARN: $error, $name oid:$oid\n");
            }
        }
    }

    return $hasError;
}

#根据文件顶部预定义的$BRANDS匹配sysDescr信息，得到设备的品牌
sub getBrand {
    my ($self) = @_;
    my $utils  = $self->{utils};
    my $snmp   = $self->{snmpSession};

    my $sysDescrOids = ['1.3.6.1.2.1.1.1.0'];

    my $sysDescr;
    my $brand;
    my $result = $snmp->get_request( -varbindlist => $sysDescrOids );
    if ( $self->_errCheck( $result, $sysDescrOids, 'sysDescr(Brand)' ) ) {
        die("ERROR: Snmp request failed.\n");
    }
    else {
        foreach my $oid (@$sysDescrOids) {
            $sysDescr = $result->{$oid};
            foreach my $aBrand (@$BRANDS) {
                if ( $sysDescr =~ /$aBrand/is ) {
                    $brand = $aBrand;
                    last;
                }
            }
            if ( defined($brand) ) {
                last;
            }
        }
    }

    if ( not defined($brand) ) {
        print("WARN: Can not get vendor from sysdescr, try to detect it by sysObjectId.\n");

        #Get sysObjectId
        my $sysObjOid = '1.3.6.1.2.1.1.2.0';
        $result = $snmp->get_request( -varbindlist => [$sysObjOid] );
        if ( $self->_errCheck( $result, [$sysObjOid], 'sysObjectId' ) ) {
            die("ERROR: Snmp request failed.\n");
        }
        else {
            my $sysObjId    = $result->{$sysObjOid};
            my $modelsArray = $utils->queryCollectDB( '_discovery_rule', { 'sysObjectId' => ".$sysObjId" }, { 'VENDOR' => 1, 'MODEL' => 1 } );
            if ( defined($modelsArray) and scalar(@$modelsArray) > 0 ) {
                my $modelInfo = $$modelsArray[0];
                my $model     = $modelInfo->{MODEL};
                $self->{DATA}->{MODEL} = $model;
                $brand = $modelInfo->{VENDOR};
                print("INFO: Detect device vendor:$brand, model:$model.\n");
            }
            else {
                print("WARN: Can not detect device vendor, please add sysObjectId:.$sysObjId and relative information in discovery_rule.\n");
            }
        }
    }

    return $brand;
}

#get simple oid value
sub _getScalar {
    my ($self)       = @_;
    my $snmp         = $self->{snmpSession};
    my $scalarOidDef = $self->{scalarOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $scalarData = $snmpHelper->getScalar( $snmp, $scalarOidDef );

    my $data = $self->{DATA};
    while ( my ( $key, $val ) = each(%$scalarData) ) {
        $data->{$key} = $val;
    }

    return;
}

#get table values from 1 or more than table oid
sub _getTable {
    my ($self)      = @_;
    my $snmp        = $self->{snmpSession};
    my $tableOidDef = $self->{tableOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $tableData  = $snmpHelper->getTable( $snmp, $tableOidDef );

    my $data = $self->{DATA};
    while ( my ( $key, $val ) = each(%$tableData) ) {
        $data->{$key} = $val;
    }

    return;
}

sub _getPortIdx {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};

    my $portIdxToNoMap = {};                                                          #序号到数字索引号的映射
    my $portIdxInfo    = $snmp->get_table( -baseoid => $commOidDef->{PORT_INDEX} );
    $self->_errCheck( $portIdxInfo, $commOidDef->{PORT_INDEX}, 'PORT_INDEX' );

    #.1.3.6.1.2.1.17.1.4.1.2.1 = INTEGER: 514
    #oid最后一位是序号，值是数字索引
    my @sortedOids = oid_lex_sort( keys(%$portIdxInfo) );
    for ( my $i = 0 ; $i <= $#sortedOids ; $i++ ) {
        my $oid = $sortedOids[$i];
        my $val = $portIdxInfo->{$oid};

        #$portIdxToNoMap->{$val} = $i + 1;

        my $portNo = int( substr( $oid, rindex( $oid, '.' ) + 1 ) );
        $portIdxToNoMap->{$val} = $portNo;
    }

    return $portIdxToNoMap;
}

sub _getPorts {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};
    my $snmpHelper = $self->{snmpHelper};

    my @ports;
    my $portsMap    = {};
    my $portIdxMap  = {};
    my $portNoMap   = {};
    my $portNameMap = {};

    my $portIdxToNoMap = $self->_getPortIdx();
    while ( my ( $idx, $no ) = each(%$portIdxToNoMap) ) {
        my $portInfo = { INDEX => $idx, NO => $no };
        $portsMap->{$idx}   = $portInfo;
        $portIdxMap->{$idx} = $portInfo;
        $portNoMap->{$no}   = $portInfo;
    }

    foreach my $portInfoKey ( 'TYPE', 'NAME', 'MAC', 'ADMIN_STATUS', 'OPER_STATUS', 'SPEED', 'MTU', 'OUT_QLEN' ) {
        my $result = $snmp->get_table( -baseoid => $commOidDef->{"PORT_$portInfoKey"} );
        $self->_errCheck( $result, $commOidDef->{"PORT_$portInfoKey"}, "PORT_$portInfoKey" );

        #.1.3.6.1.2.1.2.2.1.6.514 => 0x000fe255d930
        #.1.3.6.1.2.1.2.2.1.2.770 = STRING: Ethernet0/3
        #.1.3.6.1.2.1.2.2.1.8.770 = INTEGER: down(2)
        while ( my ( $oid, $val ) = each(%$result) ) {
            if ( $oid =~ /(\d+)$/ ) {
                my $idx      = $1;
                my $portInfo = $portsMap->{$idx};
                if ( not defined($portInfo) ) {
                    $portInfo = { INDEX => $idx, NO => undef };
                }

                if ( $portInfoKey eq 'MAC' ) {

                    #返回的值是16进制字串，需要去掉开头的0x以及每两个字节插入':'
                    $val = $snmpHelper->hex2mac($val);
                }
                elsif ( $portInfoKey eq 'ADMIN_STATUS' or $portInfoKey eq 'OPER_STATUS' ) {
                    $val = $snmpHelper->getPortStatus($val);
                }
                elsif ( $portInfoKey eq 'TYPE' ) {
                    $val = $snmpHelper->getPortType($val);
                }
                elsif ( $portInfoKey eq 'SPEED' ) {
                    $val = ( $val * 100 / 1000 / 1000 + 0.5 ) / 100;
                }
                elsif ( $portInfoKey eq 'NAME' ) {
                    $val =~ s/Eth(?=\d)/Ethernet/g;
                    $val =~ s/Gig(?=\d)/GigabitEthernet/g;
                    $portNameMap->{$val} = $portInfo;
                }

                $portInfo->{$portInfoKey} = $val;
            }
        }
    }

    if ( $self->{inspect} == 1 ) {
        my @counterFields = ( 'IN_OCTETS', 'IN_UCAST_PKTS', 'IN_NUCAST_PKTS', 'IN_DISCARDS', 'IN_ERRORS', 'IN_UNKNOWN_PROTOS', 'OUT_OCTETS', 'OUT_UCAST_PKTS', 'OUT_NUCAST_PKTS', 'OUT_DISCARDS', 'OUT_ERRORS' );

        my $preCounterMap = {};
        foreach my $portInfoKey (@counterFields) {
            my $result = $snmp->get_table( -baseoid => $commOidDef->{"PORT_$portInfoKey"} );
            $self->_errCheck( $result, $commOidDef->{"PORT_$portInfoKey"}, "PORT_$portInfoKey" );

            while ( my ( $oid, $val ) = each(%$result) ) {
                if ( $oid =~ /(\d+)$/ ) {
                    my $idx      = $1;
                    my $portInfo = $preCounterMap->{$idx};
                    if ( not defined($portInfo) ) {
                        $portInfo = {};
                        $preCounterMap->{$idx} = $portInfo;
                    }
                    $portInfo->{$portInfoKey} = int($val);
                }
            }
        }

        sleep(1);
        foreach my $portInfoKey (@counterFields) {
            my $result = $snmp->get_table( -baseoid => $commOidDef->{"PORT_$portInfoKey"} );
            $self->_errCheck( $result, $commOidDef->{"PORT_$portInfoKey"}, "PORT_$portInfoKey" );

            while ( my ( $oid, $val ) = each(%$result) ) {
                if ( $oid =~ /(\d+)$/ ) {
                    my $idx      = $1;
                    my $portInfo = $portsMap->{$idx};
                    if ( not defined($portInfo) ) {
                        next;
                    }
                    my $preCounterInfo = $preCounterMap->{$idx};
                    if ( defined($preCounterInfo) ) {
                        my $gaugeVal = int($val) - $preCounterInfo->{$portInfoKey};
                        $portInfo->{$portInfoKey} = $gaugeVal;
                    }
                }
            }
        }
    }

    my @ports = sort { $a->{NO} <=> $b->{NO} } values(%$portsMap);
    $self->{DATA}->{PORTS} = \@ports;
    $self->{portIdxMap}    = $portIdxMap;
    $self->{portNoMap}     = $portNoMap;
    $self->{portNameMap}   = $portNameMap;
}

sub _decimalMacToHex {
    my ( $self, $decimalMac ) = @_;

    my @hexParts = ();
    my @parts    = split( /\./, $decimalMac );
    foreach my $part (@parts) {
        my $hexPart = sprintf( "%02x", $part );
        push( @hexParts, $hexPart );
    }

    my $mac;
    if ( scalar(@hexParts) > 1 ) {
        $mac = join( ':', @hexParts );
    }

    return $mac;
}

sub _getMacTable {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};

    my $portMacsMap = {};
    my $portNoMap   = $self->{portNoMap};

    my $tableDef   = { MAC_TABLE => { PORT => $commOidDef->{MAC_TABLE_PORT}, MAC => $commOidDef->{MAC_TABLE_MAC} } };
    my $snmpHelper = $self->{snmpHelper};
    my $tableData  = $snmpHelper->getTable( $snmp, $tableDef );
    my $macTblData = $tableData->{MAC_TABLE};

    for ( my $i = 0 ; $i < scalar(@$macTblData) ; $i++ ) {
        my $macInfo = $$macTblData[$i];

        my $portNo   = $macInfo->{PORT};
        my $portInfo = $portNoMap->{$portNo};
        my $portDesc = $portInfo->{NAME};

        my $remoteMac = $snmpHelper->hex2mac( $macInfo->{MAC} );
        if ( $remoteMac ne '' ) {
            my $portMacInfo = $portMacsMap->{$portDesc};
            if ( not defined($portMacInfo) ) {
                $portMacInfo = { PORT => $portDesc, MAC_COUNT => 0, MACS => [] };
                $portMacsMap->{$portDesc} = $portMacInfo;
            }
            $portMacInfo->{MAC_COUNT} = 1 + $portMacInfo->{MAC_COUNT};
            my $macs = $portMacInfo->{MACS};
            push( @$macs, $remoteMac );
        }
    }

    my @macTable = values(%$portMacsMap);
    $self->{DATA}->{MAC_TABLE} = \@macTable;
}

sub _getMacTableWithVlan {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};
    my $snmpHelper = $self->{snmpHelper};
    my $portIdxMap = $self->{portIdxMap};

    my $portMacsMap     = {};
    my $portMacEntryMap = {};

    my @vlanIdArray = ();
    my $vlanStates  = $snmp->get_table( -baseoid => $commOidDef->{CISCO_VLAN_STATE} );
    while ( my ( $oid, $vlanState ) = each(%$vlanStates) ) {
        if ( $oid =~ /(\d+)$/ and $vlanState eq 1 ) {
            push( @vlanIdArray, $1 );
        }
    }

    my $options  = $self->{snmpOptions};
    my $comunity = $options->{'-community'};

    foreach my $vlanId (@vlanIdArray) {
        $options->{'-community'} = "$comunity\@$vlanId";
        my ( $vlanSnmp, $error ) = Net::SNMP->session(%$options);
        if ( !defined $vlanSnmp ) {
            print("ERROR: Create snmp session to $options->{'-host'} failed, $error\n");
            exit(-1);
        }

        my $portNoToIdxMap = {};                                                              #序号到数字索引号的映射
        my $portIdxInfo    = $vlanSnmp->get_table( -baseoid => $commOidDef->{PORT_INDEX} );
        $self->_errCheck( $portIdxInfo, $commOidDef->{PORT_INDEX}, 'PORT_INDEX' );

        #.1.3.6.1.2.1.17.1.4.1.2.1 = INTEGER: 514 #oid最后一位是序号，值是数字索引
        while ( my ( $oid, $val ) = each(%$portIdxInfo) ) {
            if ( $oid =~ /(\d+)$/ ) {
                $portNoToIdxMap->{$1} = $val;
            }
        }

        my $tableDef   = { MAC_TABLE => { PORT => $commOidDef->{MAC_TABLE_PORT}, MAC => $commOidDef->{MAC_TABLE_MAC} } };
        my $snmpHelper = $self->{snmpHelper};
        my $tableData  = $snmpHelper->getTable( $vlanSnmp, $tableDef );
        my $macTblData = $tableData->{MAC_TABLE};

        for ( my $i = 0 ; $i < scalar(@$macTblData) ; $i++ ) {
            my $macInfo = $$macTblData[$i];

            my $portNo   = $macInfo->{PORT};
            my $portIdx  = $portNoToIdxMap->{$portNo};
            my $portInfo = $portIdxMap->{$portIdx};
            my $portDesc = $portInfo->{NAME};

            my $remoteMac = $snmpHelper->hex2mac( $macInfo->{MAC} );
            if ( $remoteMac ne '' ) {
                if ( not defined( $portMacEntryMap->{"$remoteMac $portDesc"} ) ) {
                    $portMacEntryMap->{"$remoteMac $portDesc"} = 1;

                    my $portMacInfo = $portMacsMap->{$portDesc};
                    if ( not defined($portMacInfo) ) {
                        $portMacInfo = { PORT => $portDesc, MAC_COUNT => 0, MACS => [] };
                        $portMacsMap->{$portDesc} = $portMacInfo;
                    }
                    $portMacInfo->{MAC_COUNT} = 1 + $portMacInfo->{MAC_COUNT};
                    my $macs = $portMacInfo->{MACS};
                    push( @$macs, $remoteMac );
                }
            }
        }
    }

    my @macTable = values(%$portMacsMap);
    $self->{DATA}->{MAC_TABLE} = \@macTable;
}

sub _getLLDP {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};

    my $portNameMap = $self->{portNameMap};
    if ( not defined($portNameMap) ) {
        print("WARN: Can not get LLDP before get all ports.\n");
    }

    #获取邻居关系的本地端口名称列表（怀疑，这里的端口的idx和port信息里是一样的，如果是这样这里就不用采了
    my $portNoToName  = {};
    my $localPortInfo = $snmp->get_table( -baseoid => $commOidDef->{LLDP_LOCAL_PORT} );
    $self->_errCheck( $localPortInfo, $commOidDef->{LLDP_LOCAL_PORT}, 'LLDP_LOCAL_PORT' );

    #iso.0.8802.1.1.2.1.3.7.1.3.47=STRING:"Ten-GigabitEthernet1/0/47"
    #iso.0.8802.1.1.2.1.3.7.1.3.48=STRING:"Ten-GigabitEthernet1/0/48"
    while ( my ( $oid, $val ) = each(%$localPortInfo) ) {

        #oid中最后的一位数字是端口号
        if ( $oid =~ /(\d+)$/ ) {
            $portNoToName->{$1} = $val;
        }
    }

    my $remoteSysInfoMap  = {};
    my $remoteSysNameInfo = $snmp->get_table( -baseoid => $commOidDef->{LLDP_REMOTE_SYSNAME} );
    $self->_errCheck( $remoteSysNameInfo, $commOidDef->{LLDP_REMOTE_SYSNAME}, 'LLDP_REMOTE_SYSNAME' );

    #iso.0.8802.1.1.2.1,4.1.1.9.569467705.48.1=STRING:"DCA_MAN_CSW_9850_02"
    #iso.0.8802.1.1.2.1.4.1.1.9.1987299041.47.1-STRING:"DCA_MAN_CSW_9850_01"
    while ( my ( $oid, $val ) = each(%$remoteSysNameInfo) ) {
        if ( $oid =~ /(\d+\.\d+)$/ ) {
            $remoteSysInfoMap->{$1} = $val;
        }
    }

    my @neighbors;
    my $remotePortInfo = $snmp->get_table( -baseoid => $commOidDef->{LLDP_REMOTE_PORT} );
    $self->_errCheck( $remotePortInfo, $commOidDef->{LLDP_REMOTE_PORT}, 'LLDP_REMOTE_PORT' );

    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.47.1-STRING:"Ten-GigabitEtheznet1/1/6"
    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.48.1-STRING:"Ten-GigabitEtheznet1/1/6"
    while ( my ( $oid, $val ) = each(%$remotePortInfo) ) {
        if ( $oid =~ /(\d+)\.(\d+)$/ ) {

            # my $neighbor = {};
            # $neighbor->{LOCAL_NAME} = $self->{DATA}->{DEV_NAME};
            # $neighbor->{LOCAL_PORT} = $portNoToName->{$1};

            # $neighbor->{REMOTE_NAME} = $remoteSysInfoMap->{"$1.$2"};
            # $val =~ s/Eth(?=\d)/Ethernet/g;
            # $val =~ s/Gig(?=\d)/GigabitEthernet/g;
            # $neighbor->{REMOTE_PORT} = $val;
            # push( @neighbors, $neighbor );
            my $neighbor = {};
            my $portName = $portNoToName->{$1};

            my $neighborDevName  = $remoteSysInfoMap->{"$1.$2"};
            my $neighborDevName1 = $neighborDevName;
            $neighborDevName1 =~ s/\(.*?\)$//;
            $neighbor->{DEV_NAME}   = $neighborDevName;
            $neighbor->{DEV_NAME_1} = $neighborDevName1;

            $val =~ s/Eth(?=\d)/Ethernet/g;
            $val =~ s/Gig(?=\d)/GigabitEthernet/g;
            $neighbor->{PORT} = $val;

            my $portInfo  = $portNameMap->{$portName};
            my $neighbors = $portInfo->{NEIGHBORS};
            if ( not defined($neighbors) ) {
                $neighbors = [];
                $portInfo->{NEIGHBORS} = $neighbors;
            }
            push( @$neighbors, $neighbor );
        }
    }
}

sub _getCDP {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $commOidDef = $self->{commonOidDef};

    my $portNameMap = $self->{portNameMap};
    if ( not defined($portNameMap) ) {
        print("WARN: Can not get LLDP before get all ports.\n");
    }

    my $remoteSysInfoMap  = {};
    my $remoteSysNameInfo = $snmp->get_table( -baseoid => $commOidDef->{CDP_REMOTE_SYSNAME} );
    $self->_errCheck( $remoteSysNameInfo, $commOidDef->{CDP_REMOTE_SYSNAME} );

    #iso.0.8802.1.1.2.1,4.1.1.9.569467705.48.1=STRING:"DCA_MAN_CSW_9850_02"
    #iso.0.8802.1.1.2.1.4.1.1.9.1987299041.47.1-STRING:"DCA_MAN_CSW_9850_01"
    while ( my ( $oid, $val ) = each(%$remoteSysNameInfo) ) {
        if ( $oid =~ /(\d+\.\d+)$/ ) {
            $remoteSysInfoMap->{$1} = $val;
        }
    }

    my @neighbors;
    my $remotePortInfo = $snmp->get_table( -baseoid => $commOidDef->{CDP_REMOTE_PORT} );
    $self->_errCheck( $remotePortInfo, $commOidDef->{CDP_REMOTE_PORT}, 'CDP_REMOTE_PORT' );

    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.47.1-STRING:"Ten-GigabitEtheznet1/1/6"
    #iso.0.8802.1.1.2.1.4.1.1.7.569467705.48.1-STRING:"Ten-GigabitEtheznet1/1/6"
    while ( my ( $oid, $val ) = each(%$remotePortInfo) ) {
        if ( $oid =~ /(\d+)\.(\d+)$/ ) {

            # my $portIdx       = $1;
            # my $localPortInfo = $self->{portIdxMap}->{$portIdx};
            # my $neighbor      = {};
            # $neighbor->{LOCAL_NAME} = $self->{DATA}->{DEV_NAME};
            # $neighbor->{LOCAL_PORT} = $localPortInfo->{NAME};

            # $neighbor->{REMOTE_NAME} = $remoteSysInfoMap->{"$portIdx.$2"};
            # $neighbor->{REMOTE_PORT} = $val;
            # push( @neighbors, $neighbor );

            my $portIdx       = $1;
            my $localPortInfo = $self->{portIdxMap}->{$portIdx};
            my $neighbor      = {};
            my $portName      = $localPortInfo->{NAME};

            my $neighborDevName  = $remoteSysInfoMap->{"$portIdx.$2"};
            my $neighborDevName1 = $neighborDevName;
            $neighborDevName1 =~ s/\(.*?\)$//;
            $neighbor->{DEV_NAME}   = $neighborDevName;
            $neighbor->{DEV_NAME_1} = $neighborDevName1;

            $val =~ s/Eth(?=\d)/Ethernet/g;
            $val =~ s/Gig(?=\d)/GigabitEthernet/g;
            $neighbor->{PORT} = $val;

            my $portInfo  = $portNameMap->{$portName};
            my $neighbors = $portInfo->{NEIGHBORS};
            if ( not defined($neighbors) ) {
                $neighbors = [];
                $portInfo->{NEIGHBORS} = $neighbors;
            }
            push( @$neighbors, $neighbor );
        }
    }
}

sub collect {
    my ($self) = @_;

    my $brand = $self->{brand};

    #调用对应品牌的pm进行采集前的oid的设置
    $self->before();

    $self->_getScalar();
    $self->_getTable();
    $self->_getPorts();

    if ( $brand =~ /Cisco/i ) {
        $self->_getMacTableWithVlan();
        $self->_getCDP();
    }
    else {
        $self->_getMacTable();
        $self->_getLLDP();
    }

    #调用对应品牌的pm进行采集后的数据处理，用户补充数据或者调整数据
    $self->after();

    my $data = $self->{DATA};
    if ( not defined( $data->{VENDOR} ) or $data->{VENDOR} eq '' or $data->{VENDOR} eq '-' ) {
        $data->{VENDOR} = $data->{BRAND};
    }

    return $data;
}

1;

