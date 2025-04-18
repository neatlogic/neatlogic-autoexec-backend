#!/usr/bin/env perl
use FindBin;
use lib $FindBin::Bin;

package A10Snmp;

use strict;
use File::Basename;
use JSON;
use Net::SNMP qw(:snmp);
use SnmpHelper;
use Data::Dumper;

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    $self->{hasError} = 0;
    bless( $self, $class );

    $self->{snmpHelper} = SnmpHelper->new();

    my $scalarOidDef = {
        DEV_NAME => [ '1.3.6.1.2.1.1.5.0', '1.3.6.1.4.1.22610.2.4.3.2.1.2.1.1.0' ],    #sysName
        UPTIME   => '1.3.6.1.2.1.1.3.0',
        SN       => '1.3.6.1.4.1.22610.2.4.1.6.2.0',                                   #axSysSerialNumber
        IP       => '1.3.6.1.4.1.22610.2.4.3.2.1.2.1.2',                               #axServerAddress
        MODEL    => '1.3.6.1.2.1.1.1.0',                                               #sysDescr
        VENDOR   => '1.3.6.1.4.1.3375.2.1.4.1',                                        #sysProductName
        VERSION  => '1.3.6.1.4.1.22610.2.4.1.1.1.0'                                    #axSysPrimaryVersionOnDisk
    };

    my $vsOidDef = {
        VS => {
            NAME      => '1.3.6.1.4.1.22610.2.4.3.4.3.1.1.1',    #axVirtualServerPortName
            PORT      => '1.3.6.1.4.1.22610.2.4.3.4.3.1.1.3',    #axVirtualServerPortNum
            IP        => '1.3.6.1.4.1.22610.2.4.3.4.3.1.1.4',    #axVirtualServerPortAddress
            POOL_NAME => '1.3.6.1.4.1.22610.2.4.3.4.3.1.1.6',    #axVirtualServerPortServiceGroup
        },

        POOL => {
            NAME    => '1.3.6.1.4.1.22610.2.4.3.3.1.2.1.1',      #axServiceGroupName
            LB_MODE => '1.3.6.1.4.1.22610.2.4.3.3.1.2.1.3'       #axServiceGroupLbAlgorithm
        },
        POOL_MEMBER => {
            POOLNAME   => '1.3.6.1.4.1.22610.2.4.3.3.3.1.1.1',    # axServiceGroupNameInMember
            MEMBERNAME => '1.3.6.1.4.1.22610.2.4.3.3.3.1.1.3',    # axServerNameInServiceGroupMember
            MEMBERPORT => '1.3.6.1.4.1.22610.2.4.3.3.3.1.1.4'     # axServerPortNumInServiceGroupMember
        },

        MEMBER => {
            NAME         => '1.3.6.1.4.1.22610.2.4.3.2.3.1.1.1',    # axServerNameInPort
            IP           => '1.3.6.1.4.1.22610.2.4.3.2.3.1.1.4',    # axServerAddressInPort
            PORT         => '1.3.6.1.4.1.22610.2.4.3.2.3.1.1.3',    # axServerPortNum
            MONITOR_RULE => '1.3.6.1.4.1.22610.2.4.3.2.3.1.1.6'     # axServerPortHealthMonitor
        }
    };

    #my $snatOidDef = {
    #    SNAT_IP => {
    #        IP => '1.3.6.1.4.1.3375.2.2.9.5.2.1.2'                  #ltmTransAddrAddr
    #        }
    #};
    my $portsOidDef = {
        PORTS => {
            NAME => '1.3.6.1.4.1.22610.2.4.1.7.1.1.2.1.2',    #axInterfaceName
            MAC  => '1.3.6.1.4.1.22610.2.4.1.7.1.1.2.1.7',    #axInterfaceMacAddr
        }
    };

    $self->{scalarOidDef} = $scalarOidDef;
    $self->{vsOidDef}     = $vsOidDef;

    #$self->{snatOidDef}   = $snatOidDef;
    $self->{portsOidDef} = $portsOidDef;

    my $version = $args{version};
    if ( not defined($version) or $version eq '' ) {
        $version = 'snmpv2';
        $args{version} = $version;
    }
    if ( not defined( $args{retries} ) ) {
        $args{retries} = 2;
    }

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
        print("ERROR: Create snmp session to $args{host} failed, $error\n");
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
    my ( $self, $queryResult, $oid ) = @_;
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
            print("WARN: $error, $oid\n");
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

    return $scalarData;
}

sub _getPorts {
    my ($self)      = @_;
    my $snmp        = $self->{snmpSession};
    my $portsOidDef = $self->{portsOidDef};

    my $snmpHelper = $self->{snmpHelper};

    my ( $oidData, $tableData ) = $snmpHelper->getTable( $snmp, $portsOidDef, 1 );
    my $portsData = $tableData->{PORTS};

    foreach my $portInfo (@$portsData) {
        my $mac = $$portInfo{MAC};
        $mac =~ s/^0x//;
        $mac =~ s/(..)/$1:/g;
        chop($mac);
        $$portInfo{MAC}           = $mac;
        $$portInfo{_OBJ_CATEGORY} = 'LOADBALANCER';
        $$portInfo{_OBJ_TYPE}     = 'PORT';

    }
    return $portsData;
}

sub _getVS {
    my ($self)   = @_;
    my $snmp     = $self->{snmpSession};
    my $vsOidDef = $self->{vsOidDef};

    my $snmpHelper = $self->{snmpHelper};

    #my ( $oidData, $tableData ) = $snmpHelper->getTableOidAndVal( $snmp, $vsOidDef );
    my ( $oidData, $tableData ) = $snmpHelper->getTable( $snmp, $vsOidDef, 1 );
    my $vsData         = $tableData->{VS};
    my $poolData       = $tableData->{POOL};
    my $memberData     = $tableData->{MEMBER};
    my $poolMemberData = $tableData->{POOL_MEMBER};

    my $memberMap = {};
    foreach my $memberInfo (@$memberData) {

        #用member的name和port做为KEY
        $memberMap->{ $memberInfo->{NAME} . ':' . $memberInfo->{PORT} } = $memberInfo;
    }
    my $poolMap = {};
    foreach my $poolInfo (@$poolData) {
        my @members;
        my $name = $poolInfo->{NAME};
        foreach my $poolMemberInfo (@$poolMemberData) {
            if ( $name eq $poolMemberInfo->{POOLNAME} ) {
                push( @members, $memberMap->{ $poolMemberInfo->{MEMBERNAME} . ':' . $poolMemberInfo->{MEMBERPORT} } );
            }
        }
        $poolInfo->{MEMBERS} = \@members;

        my $lbMode = $poolInfo->{LB_MODE};
        if ( $lbMode eq 0 ) {
            $poolInfo->{LB_MODE} = 'roundRobin';
        }
        elsif ( $lbMode eq 1 ) {
            $poolInfo->{LB_MODE} = 'weightRoundRobin';
        }
        elsif ( $lbMode eq 2 ) {
            $poolInfo->{LB_MODE} = 'leastConnection';
        }
        $poolMap->{ $poolInfo->{NAME} } = $poolInfo;
    }
    foreach my $vsInfo (@$vsData) {
        my $poolName = $vsInfo->{POOL_NAME};
        my $vsName   = $vsInfo->{NAME};

        $vsInfo->{POOL} = $poolMap->{$poolName};

    }

    return $vsData;
}

sub collect {
    my ($self) = @_;

    my $devInfo = $self->_getScalar();
    $devInfo->{_OBJ_CATEGORY} = 'LOADBALANCER';
    $devInfo->{_OBJ_TYPE}     = 'A10';

    #$devInfo->{MGMT_IP} =  $nodeIp;

    my $vsArray = $self->_getVS();
    $devInfo->{VIRTUAL_SERVERS} = $vsArray;

    $devInfo->{PORTS} = $self->_getPorts();

    return $devInfo;
}

1;
