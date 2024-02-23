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
            NAME           => '1.3.6.1.4.1.3375.2.2.10.1.2.1.1',     #ltmVirtualServName
            IP             => '1.3.6.1.4.1.3375.2.2.10.1.2.1.3',     #ltmVirtualServAddr
            PORT           => '1.3.6.1.4.1.3375.2.2.10.1.2.1.6',     #ltmVirtualServPort
            SNAT_POOL_NAME => '1.3.6.1.4.1.3375.2.2.10.1.2.1.31',    #ltmVirtualSerSnatPoolName
            SNAT_POOL_TYPE => '1.3.6.1.4.1.3375.2.2.10.1.2.1.30',    #ltmVirtualSerSnatPoolName
            POOL_NAME      => '1.3.6.1.4.1.3375.2.2.10.1.2.1.19'     #ltmVirtualServDefaultPool
        },

        POOL => {
            NAME         => '1.3.6.1.4.1.3375.2.2.5.1.2.1.1',        #ltmPoolName
            MONITOR_RULE => '1.3.6.1.4.1.3375.2.2.5.1.2.1.17',       #ltmPoolMonitorRule
            LB_MODE      => '1.3.6.1.4.1.3375.2.2.5.1.2.1.2'         #ltmPoolLbMode
        },
        SNAT_POOL => {
            NAME    => '1.3.6.1.4.1.3375.2.2.9.9.2.1.1',             #ltmPoolName
            TYPE    => '1.3.6.1.4.1.3375.2.2.9.9.2.1.2',             #ltmPoolMonitorRule
            ADDRESS => '1.3.6.1.4.1.3375.2.2.9.9.2.1.3'              #ltmPoolLbMode
        },

        MEMBER => {
            NAME      => '1.3.6.1.4.1.3375.2.2.5.3.2.1.19',          #ltmPoolMemberNodeName
            IP        => '1.3.6.1.4.1.3375.2.2.5.3.2.1.3',           #ltmPoolMemberAddr
            PORT      => '1.3.6.1.4.1.3375.2.2.5.3.2.1.4',           #ltmPoolMemberPort
            POOL_NAME => '1.3.6.1.4.1.3375.2.2.5.3.2.1.1'            #ltmPoolMemberPoolName
        }
    };

    my $snatOidDef = {
        SNAT_IP => {
            IP => '1.3.6.1.4.1.3375.2.2.9.5.2.1.2'                   #ltmTransAddrAddr
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

    my $vsData       = $tableData->{VS};
    my $poolData     = $tableData->{POOL};
    my $memberData   = $tableData->{MEMBER};
    my $snatPoolData = $tableData->{SNAT_POOL};
    my $snatIpData   = $tableData->{SNAT_IP};

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

    # 新的数组，用于存储合并后的结果
    my @snatPools;

    # 用于存储 NAME 到地址和类型的映射
    my %name_to_data;

    # 遍历原始数组
    foreach my $entry (@$snatPoolData) {
        my $name    = $entry->{'NAME'};
        my $address = { 'IP' => $snmpHelper->hex2ip( $entry->{'ADDRESS'} ) };
        my $type    = $entry->{'TYPE'};

        # 如果 NAME 已经存在于映射中，则将 ADDRESS 和 TYPE 添加到数组中
        if ( exists $name_to_data{$name} ) {
            push @{ $name_to_data{$name}->{'ADDRESSES'} }, $address;
        }
        else {
            # 如果 NAME 还不存在于映射中，则创建新的数组
            $name_to_data{$name} = {
                'ADDRESSES' => [$address],
                'TYPE'      => $type
            };
        }
    }

    # 构建合并后的数组
    foreach my $name ( keys %name_to_data ) {
        my $data = $name_to_data{$name};
        push @snatPools, {
            '_OBJ_CATEGORY' => 'COLLECTION_LOADBALANCER',
            '_OBJ_TYPE'     => 'LOADBALANCER-SNATPOOL',
            'NAME'          => $name,
            'MEMBER_LIST'   => $data->{'ADDRESSES'},

            #'TYPE'      => $data->{'TYPE'}
        };
    }
    my $snatPoolMap = {};
    foreach my $snatPoolInfo (@snatPools) {
        $snatPoolMap->{ $snatPoolInfo->{NAME} } = $snatPoolInfo;
    }

    #foreach my $a (@merged_array){
    #    print Dumper($a);
    #}
    foreach my $vsInfo (@$vsData) {
        $vsInfo->{IP}        = $snmpHelper->hex2ip( $vsInfo->{IP} );
        $vsInfo->{POOL}      = $poolMap->{ $vsInfo->{POOL_NAME} };
        $vsInfo->{SNAT_POOL} = $snatPoolMap->{ $vsInfo->{SNAT_POOL_NAME} };
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
    $devInfo->{_OBJ_CATEGORY} = 'LOADBALANCER';
    $devInfo->{_OBJ_TYPE}     = 'F5';

    my $vsArray = $self->_getVS();
    $devInfo->{VIRTUAL_SERVERS} = $vsArray;

    my $snatArray = $self->_getSnatIp();
    $devInfo->{SNAT_IPS} = $snatArray;

    return $devInfo;
}

1;
