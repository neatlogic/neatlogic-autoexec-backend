#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");

package StorageNetApp;
use strict;

use File::Basename;
use JSON;
use Net::SNMP qw(:snmp);
use SnmpHelper;
use CollectUtils;
use Data::Dumper;

sub new {
    my ( $class, %args ) = @_;
    my $self = {};
    $self->{DATA} = {};

    my $node = $args{node};
    $self->{node} = $node;

    my $timeout = $args{timeout};
    if ( not defined($timeout) or $timeout eq '0' ) {
        $timeout = 10;
    }
    $self->{timeout} = $timeout;

    $self->{collectUtils} = CollectUtils->new();
    $self->{snmpHelper}   = SnmpHelper->new();

    bless( $self, $class );

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

    $options->{'-host'}    = $node->{host};
    $options->{'-timeout'} = $timeout;

    if ( defined( $args{community} ) ) {
        $options->{'-community'} = $args{community};
    }
    else {
        $options->{'-community'} = $node->{password};
    }
    $self->{snmpOptions} = $options;

    my ( $session, $error ) = Net::SNMP->session(%$options);
    if ( !defined $session ) {
        print("ERROR:Create snmp session to $node->{host} failed, $error\n");
        exit(-1);
    }

    #单值定义
    my $scalarOidDef = {
        DEV_NAME                  => '1.3.6.1.2.1.1.5.0',            #sysName
        UPTIME                    => '1.3.6.1.4.1.789.1.2.1.1.0',    #cpuUpTime (in hundredths of a second)
        CPU_USAGE                 => '1.3.6.1.4.1.789.1.2.1.3.0',    #cpuBusyTimePerCent
        VENDOR                    => '1.3.6.1.4.1.789.1.1.4.0',      #productVendor
        MODEL                     => '1.3.6.1.4.1.789.1.1.5.0',      #productModel
        SN                        => ['1.3.6.1.4.1.789.1.1.9.0'],    #productSerialNum
        PRODUCT_TYPE              => '1.3.6.1.4.1.789.1.1.1.0',      #productType
        PRODUCT_VERSION           => '1.3.6.1.4.1.789.1.1.2.0',      #productVersion
        OVER_TEMPERATURE          => '1.3.6.1.4.1.789.1.2.4.1.0',    #envOverTemperature no(1), yes(2)
        FAILED_FAN_COUNT          => '1.3.6.1.4.1.789.1.2.4.2.0',    #envFailedFanCount
        FAILED_POWER_SUPPLY_COUNT => '1.3.6.1.4.1.789.1.2.4.4.0',    #envFailedPowerSupplyCount
        GLOBAL_STATUS             => '1.3.6.1.4.1.789.1.2.2.4.0'     #miscGlobalStatus other(1),unknown(2),ok(3),nonCritical(4),critical(5),nonRecoverable(6)

    };

    #列表值定义
    my $tableOidDef = {
        POOL_LIST => { NAME => '1.3.6.1.4.1.789.1.5.11.1.2' },
        RAID_LIST => {
            NAME      => '1.3.6.1.4.1.789.1.5.8.1.2',
            TYPE      => '1.3.6.1.4.1.789.1.5.8.1.6',
            POOL_NAME => '1.3.6.1.4.1.789.1.5.8.1.9'
        },
        LUN_LIST => {
            NAME      => '1.3.6.1.4.1.789.1.17.15.2.1.2',
            LUN_ID    => '1.3.6.1.4.1.789.1.17.15.2.1.7',
            CAPACITY  => '1.3.6.1.4.1.789.1.17.15.2.1.28',
            RAID_NAME => '1.3.6.1.4.1.789.1.17.15.2.1.8'
        },
        HBA_LIST => { WWN => '1.3.6.1.4.1.789.1.17.16.2.1.3' }
    };

    $self->{tableOidDef} = $tableOidDef;

    $self->{snmpSession} = $session;

    END {
        local $?;
        $session->close();
    }

    return $self;
}

#get simple oid value
sub getScalar {
    my ($self)       = @_;
    my $snmp         = $self->{snmpSession};
    my $scalarOidDef = $self->{scalarOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $scalarData = $snmpHelper->getScalar( $snmp, $scalarOidDef );

    $scalarData->{UPTIME} = int( $scalarData->{UPTIME} / 86400 + 0.5 ) / 100;

    my $overTemperatureMap = { 1 => 'no', 2 => 'yes' };
    $scalarData->{OVER_TEMPERATURE} = $overTemperatureMap->{ $scalarData->{OVER_TEMPERATURE} };

    #my $globalStatusMap = {1=>'other', 2=>'unknown', 3=>'ok', 4=>'nonCritical', 5=>'critical', 6=>'nonRecoverable'};

    my $data = $self->{DATA};
    while ( my ( $key, $val ) = each(%$scalarData) ) {
        $data->{$key} = $val;
    }

    return;
}

#get table values from 1 or more than table oid
sub getPools {
    my ($self)      = @_;
    my $snmp        = $self->{snmpSession};
    my $tableOidDef = $self->{tableOidDef};

    my $snmpHelper = $self->{snmpHelper};
    my $tableData = $snmpHelper->getTable( $snmp, $tableOidDef );

    my $pools    = $tableData->{POOL_LIST};
    my $poolsMap = {};
    foreach my $poolInfo (@$pools) {
        $poolInfo->{RAIDS} = [];
        $poolsMap->{ $poolInfo->{NAME} } = $poolInfo;
    }

    my $raids    = $tableData->{RAID_LIST};
    my $raidsMap = {};
    foreach my $raidInfo (@$raids) {
        $raidInfo->{LUNS} = [];
        $raidsMap->{ $raidInfo->{NAME} } = $raidInfo;
        my $poolInfo    = $poolsMap->{ $raidInfo->{POOL_NAME} };
        my $raidsInPool = $poolInfo->{RAIDS};
        push( @$raidsInPool, $raidInfo );
    }

    my $luns = $tableData->{LUN_LIST};
    foreach my $lunInfo (@$luns) {
        my $raidInfo   = $raidsMap->{ $lunInfo->{RAID_NAME} };
        my $lunsInRaid = $raidInfo->{LUNS};
        push( @$lunsInRaid, $lunInfo );
    }

    my $hbas = $tableData->{HBA_LIST};
    foreach my $hbaInfo (@$hbas) {
        my $wwn = $hbaInfo->{WWN};
        if ( $wwn =~ /WWN\[(.*?)\]/ ) {
            $wwn = $1;
        }
        else {
            $wwn = 'Error Format';
        }
        $hbaInfo->{WWN} = $wwn;
    }

    my $data = $self->{DATA};
    $data->{STORAGE_POOLS} = $pools;

    return;
}

sub collect {
    my ($self) = @_;
    print("INFO: Try to grap NetApp by snmp.\n");

    $self->getScalar();
    $self->getPools();

    return $self->{DATA};
}

1;

