#!/usr/bin/perl
use strict;

package FCSwitchBase;
use Net::SNMP qw(:snmp);
use SnmpHelper;

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    $self->{brand} = $args{brand};
    $self->{node}  = $args{node};
    $self->{DATA}  = { PK => ['MGMT_IP'] };
    bless( $self, $class );

    $self->{snmpHelper} = SnmpHelper->new();

    my $inspect = $args{inspect};
    if ( not defined($inspect) ) {
        $inspect = 0;
    }

    my $scalarOidDef = {
        DEV_NAME         => '1.3.6.1.2.1.1.5.0',                                                                                   #sysName
        SN               => [ '1.3.6.1.2.1.47.1.1.1.1.11.1', '1.3.6.1.2.1.47.1.1.1.1.11.149', '1.3.6.1.4.1.1588.2.1.1.1.1.10' ],
        WWN              => '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.6',
        MODEL            => [ '1.3.6.1.2.1.47.1.1.1.1.2.1',     '1.3.6.1.2.1.47.1.1.1.1.13.149', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.7.3', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.5.1', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.5.2' ],
        FIRMWARE_VERSION => [ '1.3.6.1.4.1.1588.2.1.1.1.1.6.0', '1.3.6.1.2.1.47.1.1.1.1.8.22' ],                                   #sysProductVersion
        BOOT_DATE        => '1.3.6.1.4.1.1588.2.1.1.1.1.2.0',
        OPER_STATUS      => '1.3.6.1.4.1.1588.2.1.1.1.1.7.0',
        ADMIN_STATUS     => '1.3.6.1.4.1.1588.2.1.1.1.1.8.0',
        UPTIME           => '1.3.6.1.2.1.1.3.0',
        DOMAIN_ID        => '1.3.6.1.4.1.1588.2.1.1.1.2.1.0',
        PORTS_COUNT      => '1.3.6.1.2.1.2.1.0'

            #IP => '1.3.6.1.4.1.1588.2.1.1.1.1.25.0', #swEtherIPAddress
            #NETMASK => '1.3.6.1.4.1.1588.2.1.1.1.1.26.0' #swEtherIPMask
    };

    my $portCounterDef = {
        PORTS_COUNTER => {
            INDEX             => '1.3.6.1.2.1.2.2.1.1',     #ifIndex
            WWN               => '1.3.6.1.2.1.2.2.1.6',     #ifPhysAddress
            IN_OCTETS         => '1.3.6.1.2.1.2.2.1.10',    #ifInOctets
            IN_UCAST_PKTS     => '1.3.6.1.2.1.2.2.1.11',    #ifInUcastPkts
            IN_NUCAST_PKTS    => '1.3.6.1.2.1.2.2.1.12',    #ifInNUcastPkts
            IN_DISCARDS       => '1.3.6.1.2.1.2.2.1.13',    #ifInDiscards
            IN_ERRORS         => '1.3.6.1.2.1.2.2.1.14',    #ifInErrors
            IN_UNKNOWN_PROTOS => '1.3.6.1.2.1.2.2.1.15',    #ifInUnknownProtos
            OUT_OCTETS        => '1.3.6.1.2.1.2.2.1.16',    #ifOutOctets
            OUT_UCAST_PKTS    => '1.3.6.1.2.1.2.2.1.17',    #ifOutUcastPkts
            OUT_NUCAST_PKTS   => '1.3.6.1.2.1.2.2.1.18',    #ifOutNUcastPkts
            OUT_DISCARDS      => '1.3.6.1.2.1.2.2.1.19',    #ifOutDiscards
            OUT_ERRORS        => '1.3.6.1.2.1.2.2.1.20'     #ifOutErrors
        }
    };

    my $tableOidDef = {
        PORTS => {

            #1.3.6.1.4.1.1588.2.1.1.1.0.3 #swFCPortScn
            INDEX        => '1.3.6.1.2.1.2.2.1.1',          #ifIndex
            NAME         => '1.3.6.1.2.1.2.2.1.2',          #ifDescr
            TYPE         => '1.3.6.1.2.1.2.2.1.3',          #ifType
            WWN          => '1.3.6.1.2.1.2.2.1.6',          #ifPhysAddress
            ADMIN_STATUS => '1.3.6.1.2.1.2.2.1.7',          #ifAdminStatus
            OPER_STATUS  => '1.3.6.1.2.1.2.2.1.8',          #ifOperStatus
            SPEED        => '1.3.6.1.2.1.2.2.1.5',          #ifSpeed
            MTU          => '1.3.6.1.2.1.2.2.1.4',          #ifMTU
            OUT_QLEN     => '1.3.6.1.2.1.2.2.1.21'          #ifOutQLen
        },

        ZONES => {
            INDEX => '1.3.6.1.4.1.1588.2.1.1.1.2.1.1.1',
            NAME  => '1.3.6.1.4.1.1588.2.1.1.1.2.1.1.2'
        },
        IP_ADDRS => {
            IP      => '1.3.6.1.2.1.4.20.1.1',
            NETMASK => '1.3.6.1.2.1.4.20.1.3'
        },

        #TODO: 需要测试关系WWN的采集，验证LINK TABLE的形式，跟交换机的MAC TABLE是有区别的
        LINK_TABLE => {
            LOCAL_NODE_WWN => '1.3.6.1.3.94.1.12.1.3',    #connUnitLinkNodeIdX
            LOCAL_PORT_WWN => '1.3.6.1.3.94.1.12.1.5',    #connUnitLinkPortNumberX
            PEER_NODE_WWN  => '1.3.6.1.3.94.1.12.1.6',    #connUnitLinkNodeIdY
            PEER_PORT_WWN  => '1.3.6.1.3.94.1.12.1.8',    #connUnitLinkPortWwnY
        }
    };

    $self->{scalarOidDef}   = $scalarOidDef;
    $self->{tableOidDef}    = $tableOidDef;
    $self->{portCounterDef} = $portCounterDef;

    my $version = $args{version};
    if ( not defined($version) or $version eq '' ) {
        $version = 'snmpv2';
        $args{version} = $version;
    }
    if ( not defined( $args{retries} ) ) {
        $args{retries} = 2;
    }

    my $timeout = $args{timeout};
    if ( not defined($timeout) or $timeout eq '0' ) {
        $timeout = 10;
    }
    $self->{timeout} = $timeout;

    my $options = {};
    foreach my $key ( keys(%args) ) {
        if ( $key ne 'node' and $key ne 'brand' and $key ne 'inspect' ) {
            $options->{"-$key"} = $args{$key};
        }
    }
    $options->{'-maxmsgsize'} = 65535;

    my ( $session, $error ) = Net::SNMP->session(%$options);

    if ( !defined $session ) {
        print("ERROR: Create snmp session to $args{hostname} failed, $error\n");
        exit(-1);
    }

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

#get simple oid value
sub _getScalar {
    my ($self)       = @_;
    my $snmp         = $self->{snmpSession};
    my $scalarOidDef = $self->{scalarOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $scalarData = $snmpHelper->getScalar( $snmp, $scalarOidDef );

    #IP格式转换，从0x0A064156转换为可读格式
    #$scalarData->{IP} = $snmpHelper->hex2ip( $scalarData->{IP} );
    my $data = $self->{DATA};
    while ( my ( $key, $val ) = each(%$scalarData) ) {
        if ( $key eq 'ADMIN_STATUS' or $key eq 'OPER_STATUS' ) {
            $data->{$key} = $snmpHelper->getPortStatus($val);
        }
        else {
            $data->{$key} = $val;
        }
    }

    return $data;
}

sub _getTable {
    my ($self)      = @_;
    my $snmp        = $self->{snmpSession};
    my $tableOidDef = $self->{tableOidDef};
    my $snmpHelper  = $self->{snmpHelper};

    my $tableData = $snmpHelper->getTable( $snmp, $tableOidDef );

    my $portsMap  = {};
    my $portsData = $tableData->{PORTS};
    foreach my $portInfo (@$portsData) {
        $portInfo->{WWN}                = $snmpHelper->hex2mac( $portInfo->{WWN} );
        $portInfo->{ADMIN_STATUS}       = $snmpHelper->getPortStatus( $portInfo->{ADMIN_STATUS} );
        $portInfo->{OPER_STATUS}        = $snmpHelper->getPortStatus( $portInfo->{OPER_STATUS} );
        $portInfo->{TYPE}               = $snmpHelper->getPortType( $portInfo->{TYPE} );
        $portInfo->{SPEED}              = int( $portInfo->{SPEED} * 100 / 1000 / 1000 + 0.5 ) / 100;
        $portsMap->{ $portInfo->{WWN} } = $portInfo;
    }

    my $linkTable = $tableData->{LINK_TABLE};
    foreach my $linkInfo (@$linkTable) {
        $linkInfo->{LOCAL_NODE_WWN} = $snmpHelper->hex2mac( $linkInfo->{LOCAL_NODE_WWN} );
        $linkInfo->{LOCAL_PORT_WWN} = $snmpHelper->hex2mac( $linkInfo->{LOCAL_PORT_WWN} );
        $linkInfo->{PEER_NODE_WWN}  = $snmpHelper->hex2mac( $linkInfo->{PEER_NODE_WWN} );
        $linkInfo->{PEER_PORT_WWN}  = $snmpHelper->hex2mac( $linkInfo->{PEER_PORT_WWN} );
        my $localPortInfo = $portsMap->{ $linkInfo->{LOCAL_PORT_WWN} };
        if ( defined($localPortInfo) ) {
            $linkInfo->{PORT_NAME} = $localPortInfo->{NAME};

            # my $portLinkTable = $localPortInfo->{LINK_TABLE};
            # if ( not defined($portLinkTable) ) {
            #     $portLinkTable = [];
            #     $localPortInfo->{LINK_TABLE} = $portLinkTable;
            # }
            # push( @$portLinkTable, $linkInfo );
        }
        else {
            $linkInfo->{PORT_NAME} = undef;
        }
    }

    if ( $self->{inspect} == 1 ) {
        my $preCounterMap    = {};
        my $counterTblData   = $snmpHelper->getTable( $snmp, $self->{portCounterDef} );
        my $portsCounterData = $counterTblData->{PORTS_COUNTER};
        foreach my $portInfo (@$portsCounterData) {
            $preCounterMap->{ $portInfo->{WWN} } = $portInfo;
        }

        sleep(1);
        $counterTblData   = $snmpHelper->getTable( $snmp, $self->{portCounterDef} );
        $portsCounterData = $counterTblData->{PORTS_COUNTER};
        foreach my $portInfo (@$portsCounterData) {
            my $collectedPortInfo = $portsMap->{ $portInfo->{WWN} };
            my $preCounterInfo    = $preCounterMap->{ $portInfo->{WWN} };
            while ( my ( $key, $val ) = each(%$portInfo) ) {
                if ( $key ne 'WWN' and $key ne 'INDEX' ) {
                    $collectedPortInfo->{$key} = int( $portInfo->{$key} ) - int( $preCounterInfo->{$key} );
                }
            }
        }
    }

    my $data = $self->{DATA};
    while ( my ( $key, $val ) = each(%$tableData) ) {
        $data->{$key} = $val;
    }
    $data->{PORTS} = $portsData;
    $data->{ZONES} = $tableData->{ZONES};

    return $data;
}

#根据文件顶部预定义的$BRANDS匹配sysDescr信息，得到设备的品牌
sub getBrand {
    my ($self) = @_;

    my $BRANDS_MAP = {
        'Brocade'    => 'Brocade',
        'DS-C9'      => 'IBM',
        'IBM'        => 'IBM',
        'HP'         => 'HP',
        'Huawei'     => 'Huawei',
        'EMC'        => 'EMC',
        'Connectrix' => 'EMC'
    };

    my $snmp = $self->{snmpSession};

    my $sysDescrOid = [ '1.3.6.1.2.1.1.1.0', '1.3.6.1.2.1.47.1.1.1.1.2.1', '1.3.6.1.2.1.47.1.1.1.1.13.149', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.7.3', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.5.1', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.5.2' ];

    my $sysDescr;
    my $brand;
    my $result = $snmp->get_request( -varbindlist => $sysDescrOid );
    if ( $self->_errCheck( $result, $sysDescrOid, 'sysDescr(Brand)' ) ) {
        die("ERROR: Snmp request failed.\n");
    }
    else {
        for my $oid (@$sysDescrOid) {
            $sysDescr = $result->{$oid};
            foreach my $pattern ( keys(%$BRANDS_MAP) ) {
                if ( $sysDescr =~ /$pattern/is ) {
                    $brand = $BRANDS_MAP->{$pattern};
                    last;
                }
            }
            if ( defined($brand) ) {
                last;
            }
        }
        if ( not defined($brand) ) {
            print("WARN: Can not get brand from sysdescr.\n");
        }
    }

    return $brand;
}

sub collect {
    my ($self) = @_;

    #调用对应品牌的pm进行采集前的oid的设置
    $self->before();

    $self->_getScalar();
    $self->_getTable();

    my $data = $self->{DATA};
    if ( not defined( $data->{VENDOR} ) or $data->{VENDOR} eq '' ) {
        $data->{VENDOR} = $self->{brand};
    }
    if ( not defined( $data->{BRAND} ) or $data->{BRAND} eq '' ) {
        $data->{BRAND} = $self->{brand};
    }

    #调用对应品牌的pm进行采集后的数据处理，用户补充数据或者调整数据
    $self->after();

    return $data;
}

1;
