#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package FCSwitchBrocade;

use strict;
use File::Basename;
use JSON;
use Net::SNMP qw(:snmp);
use SnmpHelper;
use Data::Dumper;

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
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

    my $tblOidDef = {
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
    $self->{tblOidDef}    = $tblOidDef;

    my $version = $args{version};
    if ( not defined($version) or $version eq '' ) {
        $version = 'snmpv2';
        $args{version} = $version;
    }
    if ( not defined( $args{retries} ) ) {
        $args{retries} = 2;
    }

    my $options = {};
    foreach my $key ( keys(%args) ) {
        $options->{"-$key"} = $args{$key};
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
        $session->close();
    }

    return $self;
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

    return $scalarData;
}

sub _getTblData {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $tblOidDef  = $self->{tblOidDef};
    my $snmpHelper = $self->{snmpHelper};

    my $data = {};

    my $tableData = $snmpHelper->getTable( $snmp, $tblOidDef );
    my $portsData = $tableData->{PORTS};
    foreach my $portInfo (@$portsData) {
        $portInfo->{WWN}          = $snmpHelper->hex2mac( $portInfo->{WWN} );
        $portInfo->{ADMIN_STATUS} = $snmpHelper->getPortStatus( $portInfo->{ADMIN_STATUS} );
        $portInfo->{OPER_STATUS}  = $snmpHelper->getPortStatus( $portInfo->{OPER_STATUS} );
        $portInfo->{TYPE}         = $snmpHelper->getPortType( $portInfo->{TYPE} );
        $portInfo->{SPEED}        = int( $portInfo->{SPEED} * 100 / 1000 / 1000 + 0.5 ) / 100;
    }
    $data->{PORTS} = $portsData;

    $data->{ZONES} = $tableData->{ZONES};

    return $data;
}

sub collect {
    my ($self) = @_;

    my $devInfo = $self->_getScalar();
    my $vendor;
    my $model = $devInfo->{MODEL};
    if ( $model =~ /^Brocade/i ) {
        $vendor = 'Brocade';
    }
    elsif ( $model =~ /^DS-C9/i ) {
        $vendor = 'Cisco';
    }
    elsif ( $model =~ /^IBM/i ) {
        $vendor = 'IBM';
    }
    elsif ( $model =~ /^HP/i ) {
        $vendor = 'HP';
    }
    elsif ( $model =~ /^Huawei/i ) {
        $vendor = 'Huawei';
    }
    $devInfo->{_OBJ_CATEGORY} = 'FCSWITCH';
    $devInfo->{_OBJ_TYPE}     = $vendor;
    $devInfo->{VENDOR}        = $vendor;

    my $tblData = $self->_getTblData();
    while ( my ( $key, $data ) = each(%$tblData) ) {
        $devInfo->{$key} = $data;
    }

    return $devInfo;
}

1;
