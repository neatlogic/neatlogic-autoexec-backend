#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package F5Snmp;

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
        DEV_NAME        => '1.3.6.1.2.1.1.5.0',               #sysName
        SN              => '1.3.6.1.4.1.3375.2.1.3.3.3.0',    #sysGeneralChassisSerialNum
                                                              #IP       => '1.3.6.1.4.1.3375.2.1.2.1.1.2.1.2',                   #sysAdminIpAddr
        MODEL           => '1.3.6.1.4.1.3375.2.1.3.5.2.0',    #sysPlatformInfoMarketingName
                                                              #MODEL   => '1.3.6.1.4.1.3375.2.1.3.5.1', #sysPlatformInfoName
        VENDOR          => '1.3.6.1.4.1.3375.2.1.4.1.0',      #sysProductName
        PRODUCT_VERSION => '1.3.6.1.4.1.3375.2.1.4.2.0',      #sysProductVersion
        PRODUCT_NAME    => '1.3.6.1.4.1.3375.2.1.4.1.0',      #sysProductName
        PRODUCT_BUILD   => '1.3.6.1.4.1.3375.2.1.4.3.0',      #sysProductBuild
        PRODUCT_EDITION => '1.3.6.1.4.1.3375.2.1.4.4.0',      #sysProductEdition

        UPTIME => [ '1.3.6.1.2.1.1.3.0', '1.3.6.1.4.1.3375.1.1.50' ]    #uptime
    };

    my $vsOidDef = {
        VS => {
            NAME      => '1.3.6.1.4.1.3375.2.2.10.1.2.1.1',    #ltmVirtualServName
            IP        => '1.3.6.1.4.1.3375.2.2.10.1.2.1.3',    #ltmVirtualServAddr
            PORT      => '1.3.6.1.4.1.3375.2.2.10.1.2.1.6',    #ltmVirtualServPort
            POOL_NAME => '1.3.6.1.4.1.3375.2.2.10.1.2.1.19'    #ltmVirtualServDefaultPool
        },

        POOL => {
            NAME         => '1.3.6.1.4.1.3375.2.2.5.1.2.1.1',     #ltmPoolName
            MONITOR_RULE => '1.3.6.1.4.1.3375.2.2.5.1.2.1.17',    #ltmPoolMonitorRule
            LB_MODE      => '1.3.6.1.4.1.3375.2.2.5.1.2.1.2'      #ltmPoolLbMode
        },

        MEMBER => {
            NAME      => '1.3.6.1.4.1.3375.2.2.5.3.2.1.19',       #ltmPoolMemberNodeName
            IP        => '1.3.6.1.4.1.3375.2.2.5.3.2.1.3',        #ltmPoolMemberAddr
            PORT      => '1.3.6.1.4.1.3375.2.2.5.3.2.1.4',        #ltmPoolMemberPort
            POOL_NAME => '1.3.6.1.4.1.3375.2.2.5.3.2.1.1'         #ltmPoolMemberPoolName
        }
    };

    my $snatOidDef = {
        SNAT_IP => {
            IP => '1.3.6.1.4.1.3375.2.2.9.5.2.1.2'                #ltmTransAddrAddr
            }

            #1.3.6.1.4.1.3375.2.2.9.1.2.1.6  ltmSnatSnatpoolName
            #1.3.6.1.4.1.3375.2.2.9.1.2.1.5  ltmSnatTransAddr
    };

    $self->{scalarOidDef} = $scalarOidDef;
    $self->{vsOidDef}     = $vsOidDef;
    $self->{snatOidDef}   = $snatOidDef;

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
        if ( defined($session) ) {
            $session->close();
        }
    }

    return $self;
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
            print("WARN: $error, $name oid:$oid\n");
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
    $scalarData->{IP} = $snmpHelper->hex2ip( $scalarData->{IP} );
    $scalarData->{SN} =~ s/^\s*|\s*$//g;
    return $scalarData;
}

sub _getVS {
    my ($self)   = @_;
    my $snmp     = $self->{snmpSession};
    my $vsOidDef = $self->{vsOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $tableData  = $snmpHelper->getTable( $snmp, $vsOidDef );

    my $vsData     = $tableData->{VS};
    my $poolData   = $tableData->{POOL};
    my $memberData = $tableData->{MEMBER};
    my $snatIpData = $tableData->{SNAT_IP};

    my $poolMap = {};
    foreach my $poolInfo (@$poolData) {
        $poolMap->{ $poolInfo->{NAME} } = $poolInfo;
    }

    foreach my $memberInfo (@$memberData) {
        my $poolName = $memberInfo->{POOL_NAME};
        my $poolInfo = $poolMap->{$poolName};
        my $members  = $poolInfo->{MEMBERS};
        if ( not defined($members) ) {
            $members = [];
            $poolInfo->{MEMBERS} = $members;
        }
        $memberInfo->{IP} = $snmpHelper->hex2ip( $memberInfo->{IP} );
        push( @$members, $memberInfo );
    }

    foreach my $vsInfo (@$vsData) {
        $vsInfo->{IP}   = $snmpHelper->hex2ip( $vsInfo->{IP} );
        $vsInfo->{POOL} = $poolMap->{ $vsInfo->{POOL_NAME} };
    }

    foreach my $snatIpInfo (@$snatIpData) {
        $snatIpInfo->{IP} = $snmpHelper->hex2ip( $snatIpInfo->{IP} );
    }

    return $vsData;
}

sub _getSnatIp {
    my ($self)     = @_;
    my $snmp       = $self->{snmpSession};
    my $snatOidDef = $self->{snatOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $tableData  = $snmpHelper->getTable( $snmp, $snatOidDef );

    my $snatIpData = $tableData->{SNAT_IP};

    foreach my $snatIpInfo (@$snatIpData) {
        $snatIpInfo->{IP} = $snmpHelper->hex2ip( $snatIpInfo->{IP} );
    }

    return $snatIpData;
}

sub collect {
    my ($self) = @_;

    my $devInfo = $self->_getScalar();
    my $version = $devInfo->{PRODUCT_NAME} . ' ' . $devInfo->{PRODUCT_VERSION} . ' Build ' . $devInfo->{PRODUCT_BUILD} . ' ' . $devInfo->{PRODUCT_EDITION};

    $devInfo->{VERSION}       = $version;
    $devInfo->{_OBJ_CATEGORY} = 'LOADBLANCER';
    $devInfo->{_OBJ_TYPE}     = 'F5';

    my $vsArray = $self->_getVS();
    $devInfo->{VIRTUAL_SERVERS} = $vsArray;

    #my $snatArray = $self->_getSnatIp();
    #$devInfo->{SNAT_IPS} = $snatArray;

    return $devInfo;
}

1;
