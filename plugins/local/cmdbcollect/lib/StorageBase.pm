#!/usr/bin/perl
use strict;

package StorageBase;
use Net::OpenSSH;
use Net::SNMP qw(:snmp);
use SnmpHelper;

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    $self->{brand} = $args{brand};
    $self->{node}  = $args{node};
    $self->{inspect} = $args{inspect};
    $self->{DATA}  = { PK => ['MGMT_IP'] };
    bless( $self, $class );

    $self->{snmpHelper} = SnmpHelper->new();

    my $scalarOidDef = {
        IOS_INFO     => '1.3.6.1.2.1.1.1.0',            #sysDescr
        DEV_NAME     => '1.3.6.1.2.1.1.5.0',            #sysName
        SYS_LOCATION => '1.3.6.1.2.1.1.6.0',            #sysLocation
        UPTIME       => '1.3.6.1.2.1.1.3.0',            #cpuUpTime (in hundredths of a second)
        CPU_USAGE    => '1.3.6.1.4.1.789.1.2.1.3.0',    #cpuBusyTimePerCent
    };

    my $tableOidDef = {};

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
        if ( $key ne 'node' and $key ne 'brand' and $key ne 'inspect' ) {
            $options->{"-$key"} = $args{$key};
        }
    }
    $options->{'-maxmsgsize'} = 65535;

    my ( $session, $error ) = Net::SNMP->session(%$options);

    if ( !defined $session ) {
        print("ERROR:Create snmp session to $args{hostname} failed, $error\n");
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
            if ( ref($oid) eq 'ARRAY' ) {
                print( "WARN: $error, oids:", join( ', ', @$oid ), "\n" );
            }
            else {
                print("WARN: $error, $oid\n");
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

    $scalarData->{UPTIME} = int( $scalarData->{UPTIME} );

    my $overTemperatureMap = { 1 => 'no', 2 => 'yes' };
    $scalarData->{OVER_TEMPERATURE} = $overTemperatureMap->{ $scalarData->{OVER_TEMPERATURE} };

    my $globalStatusMap = { 1 => 'other', 2 => 'unknown', 3 => 'ok', 4 => 'nonCritical', 5 => 'critical', 6 => 'nonRecoverable' };
    $scalarData->{GLOBAL_STATUS} = $globalStatusMap->{ $scalarData->{GLOBAL_STATUS} };

    my $data = $self->{DATA};
    while ( my ( $key, $val ) = each(%$scalarData) ) {
        $data->{$key} = $val;
    }

    return $data;
}

sub _getTable {
    my ($self)      = @_;
    my $snmp        = $self->{snmpSession};
    my $tableOidDef = $self->{tableOidDef};
    my $snmpHelper  = $self->{snmpHelper};

    my $tableData = $snmpHelper->getTable( $snmp, $tableOidDef );

    my $data = $self->{DATA};
    while ( my ( $key, $val ) = each(%$tableData) ) {
        $data->{$key} = $val;
    }

    return $data;
}

#根据文件顶部预定义的$BRANDS匹配sysDescr信息，得到设备的品牌
sub getBrand {
    my ($self) = @_;

    my $BRANDS_MAP = {
        'HP_3PAR'    => 'HP_3PAR',
        'Brocade'    => 'Brocade',
        'DS-C9'      => 'IBM',
        'IBM'        => 'IBM',
        'HP'         => 'HP',
        'Huawei'     => 'Huawei',
        'Vplex'      => 'Vplex',
        'Unity'      => 'Vplex',
        'EMC'        => 'EMC',
        'Connectrix' => 'EMC'
    };

    my $snmp = $self->{snmpSession};

    my $sysDescrOid = [ '1.3.6.1.2.1.1.1.0', '1.3.6.1.2.1.1.5.0' ];

    my $sysDescr;
    my $brand;
    my $result = $snmp->get_request( -varbindlist => $sysDescrOid );
    if ( $self->_errCheck( $result, $sysDescrOid ) ) {
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
