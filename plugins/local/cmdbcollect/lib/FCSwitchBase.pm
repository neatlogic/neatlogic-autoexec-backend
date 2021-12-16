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

    my $scalarOidDef = {
        DEV_NAME => '1.3.6.1.2.1.1.5',                                                                                                                                                                     #sysName
        SN       => [ '1.3.6.1.2.1.47.1.1.1.1.11.1', '1.3.6.1.2.1.47.1.1.1.1.11.149', '1.3.6.1.4.1.1588.2.1.1.1.1.10' ],
        MODEL    => [ '1.3.6.1.2.1.47.1.1.1.1.2.1', '1.3.6.1.2.1.47.1.1.1.1.13.149', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.7.3', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.5.1', '1.3.6.1.4.1.1588.2.1.1.1.7.2.1.5.2' ],
        FIRMWARE_VERSION => [ '1.3.6.1.4.1.1588.2.1.1.1.1.6', '1.3.6.1.2.1.47.1.1.1.1.8.22' ],                                                                                                             #sysProductVersion
        BOOT_DATE        => '1.3.6.1.4.1.1588.2.1.1.1.1.2',
        DOMAIN_ID        => '1.3.6.1.4.1.1588.2.1.1.1.2.1.0', #uptime
        PORTS_COUNT      => '1.3.6.1.2.1.2.1.0'
    };

    my $tableOidDef = {
        PORTS => {
            INDEX        => '1.3.6.1.2.1.2.2.1.1',                                                                                                                                                         #ifIndex
            NAME         => '1.3.6.1.2.1.2.2.1.2',                                                                                                                                                         #ifDescr
            TYPE         => '1.3.6.1.2.1.2.2.1.3',                                                                                                                                                         #ifType
            WWN          => '1.3.6.1.2.1.2.2.1.6',                                                                                                                                                         #ifPhysAddress
            ADMIN_STATUS => '1.3.6.1.2.1.2.2.1.7',                                                                                                                                                         #ifAdminStatus
            OPER_STATUS  => '1.3.6.1.2.1.2.2.1.8',                                                                                                                                                         #ifOperStatus
            SPEED        => '1.3.6.1.2.1.2.2.1.5',                                                                                                                                                         #ifSpeed
            MTU          => '1.3.6.1.2.1.2.2.1.4',                                                                                                                                                         #ifMTU
        },
        ZONES => {
            INDEX => '1.3.6.1.4.1.1588.2.1.1.1.2.1.1.1',
            NAME  => '1.3.6.1.4.1.1588.2.1.1.1.2.1.1.2'
        }
    };

    $self->{scalarOidDef} = $scalarOidDef;
    $self->{tableOidDef}  = $tableOidDef;

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
        if ( $key ne 'node' and $key ne 'brand' ) {
            $options->{"-$key"} = $args{$key};
        }
    }
    $options->{'-maxmsgsize'} = 65535;

    my ( $session, $error ) = Net::SNMP->session(%$options);

    if ( !defined $session ) {
        print("ERROR:Create snmp session to $args{host} failed, $error\n");
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
    my ( $self, $collector ) = @_;

    #$collector->addScalarOid( SN => '1.3.6.1.2.1.47.1.1.1.1.11.1' );
    #$collector->addTableOid( PORTS_TABLE_FOR_TEST => [ { NAME => '1.3.6.1.2.1.2.2.1.2' }, { MAC => '1.3.6.1.2.1.2.2.1.6' } ] );
    #$collector->setCommonOid( PORT_TYPE => '1.3.6.1.2.1.2.2.1.3' );
}

#重载此方法，进行数据调整，或者补充其他非SNMP数据
sub after {
    my ( $self, $collector ) = @_;

    #my $data = $collector->{DATA};
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
    my ( $self, $queryResult, $oid ) = @_;
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
            print("WARN: $error, $oid\n");
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
        $data->{$key} = $val;
    }

    return $data;
}

sub _getTblData {
    my ($self)      = @_;
    my $snmp        = $self->{snmpSession};
    my $tableOidDef = $self->{tableOidDef};
    my $snmpHelper  = $self->{snmpHelper};

    my $tableData = $snmpHelper->getTable( $snmp, $tableOidDef );
    my $portsData = $tableData->{PORTS};
    foreach my $portInfo (@$portsData) {
        $portInfo->{WWN}          = $snmpHelper->hex2mac( $portInfo->{WWN} );
        $portInfo->{ADMIN_STATUS} = $snmpHelper->getPortStatus( $portInfo->{ADMIN_STATUS} );
        $portInfo->{OPER_STATUS}  = $snmpHelper->getPortStatus( $portInfo->{OPER_STATUS} );
        $portInfo->{TYPE}         = $snmpHelper->getPortType( $portInfo->{TYPE} );
        $portInfo->{SPEED}        = int( $portInfo->{SPEED} * 100 / 1000 / 1000 + 0.5 ) / 100;
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
        'Brocade' => 'Brocade',
        'DS-C9'   => 'IBM',
        'IBM'     => 'IBM',
        'HP'      => 'HP',
        'Huawei'  => 'Huawei'
    };

    my $snmp = $self->{snmpSession};

    my $sysDescrOid = $self->{scalarOidDef}->{MODEL};

    my $sysDescr;
    my $brand;
    my $result = $snmp->get_request( -varbindlist => [$sysDescrOid] );
    if ( $self->_errCheck( $result, $sysDescrOid ) ) {
        die("ERROR: Snmp request failed.\n");
    }
    else {
        $sysDescr = $result->{$sysDescrOid};
        foreach my $pattern ( keys(%$BRANDS_MAP) ) {
            if ( $sysDescr =~ /$pattern/is ) {
                $brand = $BRANDS_MAP->{$pattern};
                last;
            }
        }
    }

    if ( not defined($brand) ) {
        print("WARN: Can not get predefined brand from sysdescr:\n$sysDescr\n");
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