#!/usr/bin/perl
use strict;

package FCSwitchBase;
use Net::SNMP qw(:snmp);
use SnmpHelper;

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    $self->{hasError}   = 0;
    $self->{brand}      = $args{brand};
    $self->{sshAccount} = $args{sshAccount};
    $self->{node}       = $args{node};
    $self->{DATA}       = { PK => ['MGMT_IP'] };
    bless( $self, $class );

    $self->{snmpHelper} = SnmpHelper->new();

    my $inspect = $args{inspect};
    if ( not defined($inspect) ) {
        $inspect = 0;
    }
    $self->{inspect} = $inspect;

    my $scalarOidDef = {
        DEV_NAME         => '1.3.6.1.2.1.1.5.0',                                                                                   #sysName
        SN               => [ '1.3.6.1.2.1.47.1.1.1.1.11.1', '1.3.6.1.2.1.47.1.1.1.1.11.149', '1.3.6.1.4.1.1588.2.1.1.1.1.10' ],
        WWNN             => '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.6',
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

        # PORTS_COUNTER => {
        #     INDEX             => '1.3.6.1.2.1.2.2.1.1',     #ifIndex
        #     WWPN              => '1.3.6.1.2.1.2.2.1.6',     #ifPhysAddress
        #     IN_OCTETS         => '1.3.6.1.2.1.2.2.1.10',    #ifInOctets
        #     IN_UCAST_PKTS     => '1.3.6.1.2.1.2.2.1.11',    #ifInUcastPkts
        #     IN_NUCAST_PKTS    => '1.3.6.1.2.1.2.2.1.12',    #ifInNUcastPkts
        #     IN_DISCARDS       => '1.3.6.1.2.1.2.2.1.13',    #ifInDiscards
        #     IN_ERRORS         => '1.3.6.1.2.1.2.2.1.14',    #ifInErrors
        #     IN_UNKNOWN_PROTOS => '1.3.6.1.2.1.2.2.1.15',    #ifInUnknownProtos
        #     OUT_OCTETS        => '1.3.6.1.2.1.2.2.1.16',    #ifOutOctets
        #     OUT_UCAST_PKTS    => '1.3.6.1.2.1.2.2.1.17',    #ifOutUcastPkts
        #     OUT_NUCAST_PKTS   => '1.3.6.1.2.1.2.2.1.18',    #ifOutNUcastPkts
        #     OUT_DISCARDS      => '1.3.6.1.2.1.2.2.1.19',    #ifOutDiscards
        #     OUT_ERRORS        => '1.3.6.1.2.1.2.2.1.20'     #ifOutErrors
        # }
        PORTS_COUNTER => {
            INDEX            => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.1',     #swFCportIndex
            WWPN             => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.34',    #swFCPortWwn
            TX_WORDS         => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.11',    #swFCPortTxWords
            RX_WORDS         => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.12',    #swFCPortRxWords
            TX_FRAMES        => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.13',    #swFCPortTxFrames
            RX_FRAMES        => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.14',    #swFCPortRxFrames
            RX_C2FRAMES      => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.15',    #swFCPortRxC2Frames
            RX_C3FRAMES      => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.16',    #swFCPortRxC3Frames
            RX_LCS           => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.17',    #swFCPortRxLCs
            RX_MCASTS        => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.18',    #swFCPortRxMcasts
            TOO_MANY_RDYS    => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.19',    #swFCPortTooManyRdys
            NO_TX_CREDITS    => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.20',    #swFCPortNoTxCredits
            RX_ENC_IN_FRS    => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.21',    #swFCPortRxEncInFrs
            RX_CRCS          => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.22',    #swFCPortRxCrcs
            RX_TRUNCS        => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.23',    #swFCPortRxTruncs
            RX_TOO_LONGS     => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.24',    #swFCPortRxTooLongs
            RX_BAD_EOFS      => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.25',    #swFCPortRxBadEofs
            RX_ENC_OUT_FRS   => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.26',    #swFCPortRxEncOutFrs
            RX_BAD_OS        => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.27',    #swFCPortRxBadOs
            C3_DISCARDS      => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.28',    #swFCPortC3Discards
            MCAST_TIMED_OUTS => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.29',    #swFCPortMcastTimedOuts
            TX_MCASTS        => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.30',    #swFCPortTxMcasts
            LIP_INS          => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.31',    #swFCPortLipIns
            LIP_OUTS         => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.32'     #swFCPortLipOuts
        }
    };

    my $tableOidDef = {

        # PORTS => {

        #     #1.3.6.1.4.1.1588.2.1.1.1.0.3 #swFCPortScn
        #     INDEX        => '1.3.6.1.2.1.2.2.1.1',          #ifIndex
        #     NAME         => '1.3.6.1.2.1.2.2.1.2',          #ifDescr
        #     TYPE         => '1.3.6.1.2.1.2.2.1.3',          #ifType
        #     WWPN         => '1.3.6.1.2.1.2.2.1.6',          #ifPhysAddress
        #     ADMIN_STATUS => '1.3.6.1.2.1.2.2.1.7',          #ifAdminStatus
        #     OPER_STATUS  => '1.3.6.1.2.1.2.2.1.8',          #ifOperStatus
        #     SPEED        => '1.3.6.1.2.1.2.2.1.5',          #ifSpeed
        #     MTU          => '1.3.6.1.2.1.2.2.1.4',          #ifMTU
        #     OUT_QLEN     => '1.3.6.1.2.1.2.2.1.21'          #ifOutQLen
        # },

        PORTS => {

            #1.3.6.1.4.1.1588.2.1.1.1.0.3 #swFCPortScn
            INDEX        => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.1',     #swFCportIndex
            NAME         => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.36',    #swFCPortName
            PORT         => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.37',    #swFCPortSpecifier
            TYPE         => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.2',     #swFCPortType
            WWPN         => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.34',    #swFCPortWwn
            ADMIN_STATUS => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.5',     #swFCPortAdminStatus
            OPER_STATUS  => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.4',     #swFCPortOPStatus
            LINK_STATE   => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.6',     #swFCPortLinkState
            PHY_STATE    => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.3',     #swFCPortPhyState
            SPEED        => '1.3.6.1.4.1.1588.2.1.1.1.6.2.1.35'     #swFCPortSpeed
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
            WWNN             => '1.3.6.1.3.94.1.12.1.3',    #connUnitLinkNodeIdX
            PORT_NUMBER      => '1.3.6.1.3.94.1.12.1.4',    #connUnitLinkPortNumberX
            WWPN             => '1.3.6.1.3.94.1.12.1.5',    #connUnitLinkPortWwnX
            PEER_WWNN        => '1.3.6.1.3.94.1.12.1.6',    #connUnitLinkNodeIdY
            PEER_PORT_NUMBER => '1.3.6.1.3.94.1.12.1.7',    #connUnitLinkPortNumberY
            PEER_WWPN        => '1.3.6.1.3.94.1.12.1.8',    #connUnitLinkPortWwnY
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

    my $noneSnmpOpt = {
        node       => 1,
        brand      => 1,
        inspect    => 1,
        sshAccount => 1,
        objType    => 1
    };
    my $options = {};
    foreach my $key ( keys(%args) ) {
        if ( not defined( $noneSnmpOpt->{$key} ) ) {
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

    $self->init();

    return $self;
}

#下游类通过重载这个方法进行类的初始化
sub init {
    my ($self) = @_;
    return;
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
    my $resultError = 0;
    my $snmp        = $self->{snmpSession};
    if ( not defined($queryResult) ) {
        $resultError = 1;
        my $error = $snmp->error();
        if ( $error =~ /^No response/i ) {
            $self->{hasError} = 1;
            print("ERROR: $error, snmp failed, exit.\n");
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

    return $resultError;
}

#get simple oid value
sub _getScalar {
    my ($self)       = @_;
    my $snmp         = $self->{snmpSession};
    my $scalarOidDef = $self->{scalarOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $scalarData = $snmpHelper->getScalar( $snmp, $scalarOidDef );

    #"BOOT_DATE" : "Thu Mar 30 05:46:28 2023\n",
    my $bootDate = $scalarData->{BOOT_DATE};
    $bootDate =~ s/\n//g;
    $scalarData->{BOOT_DATE} = $bootDate;

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

    # foreach my $portInfo (@$portsData) {
    #     $portInfo->{WWPN}                = $snmpHelper->hex2mac( $portInfo->{WWPN} );
    #     $portInfo->{ADMIN_STATUS}        = $snmpHelper->getPortStatus( $portInfo->{ADMIN_STATUS} );
    #     $portInfo->{OPER_STATUS}         = $snmpHelper->getPortStatus( $portInfo->{OPER_STATUS} );
    #     $portInfo->{TYPE}                = $snmpHelper->getPortType( $portInfo->{TYPE} );
    #     $portInfo->{SPEED}               = int( $portInfo->{SPEED} * 100 / 1000 / 1000 + 0.5 ) / 100;
    #     $portsMap->{ $portInfo->{WWPN} } = $portInfo;
    # }
    #my $fcportsData = $tableData->{PORTS};
    foreach my $portInfo (@$portsData) {
        $portInfo->{_OBJ_CATEGORY} = "FCDEV";
        $portInfo->{_OBJ_TYPE}     = "FCSWITCH-PORT";
        $portInfo->{DOMAIN_IDX}    = $self->{DATA}->{DOMAIN_ID} . "," . $portInfo->{PORT};
        $portInfo->{WWPN}          = $snmpHelper->hex2mac( $portInfo->{WWPN} );
        $portInfo->{ADMIN_STATUS}  = $snmpHelper->getPortStatus( $portInfo->{ADMIN_STATUS} );
        $portInfo->{OPER_STATUS}   = $snmpHelper->getPortStatus( $portInfo->{OPER_STATUS} );
        $portInfo->{LINK_STATE}    = $snmpHelper->getPortStatus( $portInfo->{LINK_STATE} );
        $portInfo->{PHY_STATE}     = $snmpHelper->getPortStatus( $portInfo->{PHY_STATE} );
        $portInfo->{TYPE}          = $snmpHelper->getPortType( $portInfo->{TYPE} );

        $portsMap->{ $portInfo->{WWPN} } = $portInfo;
    }

    #计算本地端口往外连接的连接数量，冗余回填本地端口名
    my $linkCountMap         = {};
    my $linkTable            = $tableData->{LINK_TABLE};
    my $localWwpnPeerWwpnMap = {};
    foreach my $linkInfo (@$linkTable) {
        my $localWwnn = $snmpHelper->hex2mac( $linkInfo->{WWNN} );
        my $localWwpn = $snmpHelper->hex2mac( $linkInfo->{WWPN} );
        my $peerWwnn  = $snmpHelper->hex2mac( $linkInfo->{PEER_WWNN} );
        my $peerWwpn  = $snmpHelper->hex2mac( $linkInfo->{PEER_WWPN} );

        $linkInfo->{WWNN}                   = $localWwnn;
        $linkInfo->{WWPN}                   = $localWwpn;
        $linkInfo->{PEER_WWNN}              = $peerWwnn;
        $linkInfo->{PEER_WWPN}              = $peerWwpn;
        $localWwpnPeerWwpnMap->{$localWwpn} = $peerWwpn;
        my $keyStr    = "$localWwnn-$localWwpn";
        my $linkCount = $linkCountMap->{$keyStr};
        if ( not defined($linkCount) ) {
            $linkCount = 0;
        }
        $linkCountMap->{$keyStr} = $linkCount + 1;

        my $localPortInfo = $portsMap->{ $linkInfo->{WWPN} };
        if ( not defined($localPortInfo) ) {
            $localPortInfo = $portsMap->{ $linkInfo->{WWNN} };
        }
        if ( defined($localPortInfo) ) {
            $linkInfo->{PORT_NAME}  = $localPortInfo->{NAME};
            $linkInfo->{DOMAIN_IDX} = $localPortInfo->{DOMAIN_IDX};
        }
        else {
            $linkInfo->{PORT_NAME}  = undef;
            $linkInfo->{DOMAIN_IDX} = undef;
        }
    }

    foreach my $portInfo (@$portsData) {

        #设置端口的对端WWPN
        $portInfo->{PEER_WWPN} = $localWwpnPeerWwpnMap->{ $portInfo->{WWPN} };
    }
    foreach my $linkInfo (@$linkTable) {
        my $localWwnn = $linkInfo->{WWNN};
        my $localWwpn = $linkInfo->{WWPN};
        $linkInfo->{LINK_COUNT} = $linkCountMap->{"$localWwnn-$localWwpn"};
    }

    #端口连接数量统计完成

    my $data = $self->{DATA};

    if ( $self->{inspect} == 1 ) {

        #巡检需要统计各个端口每秒的包流量
        my $preCounterMap    = {};
        my $counterTblData   = $snmpHelper->getTable( $snmp, $self->{portCounterDef} );
        my $portsCounterData = $counterTblData->{PORTS_COUNTER};
        foreach my $portCounterInfo (@$portsCounterData) {
            $portCounterInfo->{WWPN} = $snmpHelper->hex2mac( $portCounterInfo->{WWPN} );

            $preCounterMap->{ $portCounterInfo->{WWPN} } = $portCounterInfo;
        }

        sleep(1);
        $counterTblData   = $snmpHelper->getTable( $snmp, $self->{portCounterDef} );
        $portsCounterData = $counterTblData->{PORTS_COUNTER};
        foreach my $portCounterInfo (@$portsCounterData) {
            $portCounterInfo->{WWPN} = $snmpHelper->hex2mac( $portCounterInfo->{WWPN} );

            my $collectedPortInfo = $portsMap->{ $portCounterInfo->{WWPN} };
            my $preCounterInfo    = $preCounterMap->{ $portCounterInfo->{WWPN} };
            while ( my ( $key, $val ) = each(%$portCounterInfo) ) {
                if ( $key ne 'WWPN' and $key ne 'INDEX' ) {
                    $portCounterInfo->{$key} = int( $portCounterInfo->{$key} ) - int( $preCounterInfo->{$key} );
                }
            }
        }
        $data->{PORTS_COUNTER} = $portsCounterData;
    }

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
        'Brocade'          => 'Brocade',
        'G620'             => 'Brocade',
        'SWG620'           => 'Brocade',
        '2498-B80'         => 'Brocade',
        'DS_6620B'         => 'Brocade',
        'EM-6510-24-16G-R' => 'Brocade',
        '6505'             => 'Brocade',
        '6510'             => 'Brocade',
        '6520'             => 'Brocade',
        '6505'             => 'Brocade',
        'IBM_2498_F48'     => 'Brocade',
        'DS-C9'            => 'IBM',
        'IBM'              => 'IBM',
        'TYPE 2498'        => 'IBM',
        '2005-B16'         => 'IBM',
        '2498-B24'         => 'IBM',
        'F96'              => 'IBM',
        'HP'               => 'HP',
        'Huawei'           => 'Huawei',
        'HU'               => 'Huawei',
        'SNS'              => 'Huawei',
        'EMC'              => 'EMC',
        'Connectrix'       => 'EMC',
        'DS_6620B'         => 'DELL',
        'DS6620B'          => 'DELL',
        '6620B'            => 'DELL'
    };

    my $snmp = $self->{snmpSession};

    my $sysDescrOid = [ '1.3.6.1.2.1.1.1.0', '1.3.6.1.2.1.47.1.1.1.1.2.1', '1.3.6.1.2.1.47.1.1.1.1.13.149', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.7.3', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.5.1', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.5.2' ];

    my $sysDescr;
    my $brand;
    my $result = $snmp->get_request( -varbindlist => $sysDescrOid );
    if ( $self->_errCheck( $result, $sysDescrOid, 'sysDescr(Brand)' ) == 0 ) {
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

    eval {
        $self->_getScalar();
        $self->_getTable();
    };
    if ($@) {
        my $errMsg = $@;
        $errMsg =~ s/ at\s*.*$//;
        print($errMsg );
    }

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
