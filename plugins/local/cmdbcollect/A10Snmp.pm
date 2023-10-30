#!/usr/bin/perl
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
    bless( $self, $class );

    $self->{snmpHelper} = SnmpHelper->new();

    my $scalarOidDef = {
        DEV_NAME => [ '1.3.6.1.2.1.1.5', '1.3.6.1.4.1.22610.2.4.3.2.1.2.1.1' ],    #sysName
        UPTIME   => '1.3.6.1.2.1.1.3.0',
        SN       => '1.3.6.1.4.1.22610.2.4.1.6.2',                                 #axSysSerialNumber
        IP       => '1.3.6.1.4.1.22610.2.4.3.2.1.2.1.2',                           #axServerAddress
        MODEL    => '1.3.6.1.2.1.1.1',                                             #sysDescr
        VENDOR   => '1.3.6.1.4.1.3375.2.1.4.1.0',                                  #sysProductName
        VERSION  => '1.3.6.1.4.1.22610.2.4.1.1.1'                                  #axSysPrimaryVersionOnDisk
    };

    my $vsOidDef = {
        VS => {
            NAME      => '1.3.6.1.4.1.22610.2.4.3.4.1.2.1.1',    #axVirtualServerName
            IP        => '1.3.6.1.4.1.22610.2.4.3.4.1.2.1.2',    #ltmVirtualServAddr
            POOL_NAME => '1.3.6.1.4.1.22610.2.4.3.4.3.1.1.6'     #axVirtualServerPortServiceGroup
        },

        POOL => {
            NAME         => '1.3.6.1.4.1.22610.2.4.3.3.1.2.1.1',    #axServiceGroupName
            MONITOR_RULE => undef,
            LB_MODE      => '1.3.6.1.4.1.22610.2.4.3.3.1.2.1.3'     #axServiceGroupLbAlgorithm
        },

        MEMBER => {
            NAME         => '1.3.6.1.4.1.22610.2.4.3.3.3.1.1.3',    #axServerNameInServiceGroupMember
            POOL_NAME    => '1.3.6.1.4.1.22610.2.4.3.3.3.1.1.1',    #axServiceGroupNameInMember
            IP           => '1.3.6.1.4.1.22610.2.4.3.2.1.2.1.2',    #axServerAddress
            PORT         => '1.3.6.1.4.1.22610.2.4.3.3.3.1.1.4',    #axServerPortNumInServiceGroupMember
            MONITOR_RULE => '1.3.6.1.4.1.22610.2.4.3.2.1.2.1.4'     #axServerHealthMonitor
        }
    };

    my $snatOidDef = {
        SNAT_IP => {
            IP => '1.3.6.1.4.1.3375.2.2.9.5.2.1.2'                  #ltmTransAddrAddr
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

    return $scalarData;
}

sub _getVS {
    my ($self)   = @_;
    my $snmp     = $self->{snmpSession};
    my $vsOidDef = $self->{vsOidDef};

    my $snmpHelper = $self->{snmpHelper};

    #my ( $oidData, $tableData ) = $snmpHelper->getTableOidAndVal( $snmp, $vsOidDef );
    my ( $oidData, $tableData ) = $snmpHelper->getTable( $snmp, $vsOidDef, 1 );

    my $poolMap  = {};
    my $poolData = $tableData->{POOL};
    foreach my $poolInfo (@$poolData) {
        $poolMap->{ $poolInfo->{NAME} } = $poolInfo;
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
    }

    #这里有一个IP的对应处理逻辑，可能也是不一定需要的，要根据实际情况来调整
    my $memberIdxMap  = {};
    my $memberData    = $tableData->{MEMBER};
    my $memberOidData = $tableData->{MEMBER};
    for ( my $i = 0 ; $i < scalar(@$memberData) ; $i++ ) {
        my $memberInfo    = $$memberData[$i];
        my $memberOidInfo = $$memberOidData[$i];

        my $memberName = $memberInfo->{NAME};
        my $memberOid  = $memberOidInfo->{NAME};
        $memberOid =~ /(\d+)\.(\d+)$/;
        my $memberNameIdx = $1;
        my $memberPort    = $2;
        $memberIdxMap->{$memberNameIdx} = $memberInfo;
    }
    ###############################################

    for ( my $i = 0 ; $i < scalar(@$memberData) ; $i++ ) {
        my $memberInfo    = $$memberData[$i];
        my $memberOidInfo = $$memberOidData[$i];

        #根据memberIdx获取IP，这个涉及IP和member的对应关系的问题，这里的逻辑可能是不需要的。
        my $ipOid = $memberOidInfo->{IP};
        $ipOid =~ /(\d+)$/;
        my $memberidx = $1;
        $memberInfo->{IP} = $memberIdxMap->{$memberidx}->{IP};
        ##############################

        #根据POOL_NAME嵌入POOL对象
        my $poolInfo = $poolMap->{ $memberInfo->{POOL_NAME} };
        $poolInfo->{MEMBER} = $memberInfo;
    }

    my $vsData    = $tableData->{VS};
    my $vsOidData = $oidData->{VS};

    #感觉这一段是不需要的，因为根据VS来检索，use pool和vs排序后其实是一一对应的，不需要通过oid的index来mappingVS和pool
    my $vsIdx2PoolMap = {};
    for ( my $i = 0 ; $i < scalar(@$vsData) ; $i++ ) {
        my $vsInfo    = $$vsData[$i];
        my $vsOidInfo = $vsOidData->{ $vsInfo->{INDEX} };

        my $usePoolOid = $vsOidInfo->{POOL_NAME};

        #POOL_NAME属性的OID的倒数第三段数字是VS的index号
        $usePoolOid =~ /(\d+)\.\d+\.\d+$/;
        my $vsIdx = $1;
        $vsIdx2PoolMap->{$vsIdx} = $vsInfo->{POOL_NAME};
    }
    ##################################

    for ( my $i = 0 ; $i < scalar(@$vsData) ; $i++ ) {
        my $vsInfo = $$vsData[$i];
        my $vsIdx  = $vsInfo->{INDEX};
        $vsInfo->{POOL_NAME} = $vsIdx2PoolMap->{$vsIdx};
        $vsInfo->{POOL}      = $poolMap->{ $vsInfo->{POOL_NAME} };
    }

    #通过OID的关联计算VS引用的POOL NAME结束，这一段可能不是一定需要的

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

    return $devInfo;
}

1;
