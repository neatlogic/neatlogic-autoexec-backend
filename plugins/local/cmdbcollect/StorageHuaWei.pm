#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");

package StorageHuaWei;
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
    $options->{'-hostname'}    = $node->{host};
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
    #TODO: 需要确认这些OID最后是否需要加上“.0”，大部分简单值的OID后面都是有.0
    my $scalarOidDef = {
        SN            => ['1.3.6.1.4.1.34774.4.1.1.1'],    #deviceId
        VERSION       => '1.3.6.1.4.1.34774.4.1.1.6',      #Version
        DEV_NAME      => '1.3.6.1.2.1.1.5.0',              #sysName
        GLOBAL_STATUS => '1.3.6.1.4.1.34774.4.1.1.3',      #status
        CPU_USAGE     => '1.3.6.1.4.1.789.1.2.1.3.0',      #cpuBusyTimePerCent
        VENDOR        => '1.3.6.1.4.1.789.1.1.4.0'         #productVendor
    };

    #列表值定义
    my $tableOidDef = {
        CTRL_LIST => {
            NAME    => '1.3.6.1.4.1.34774.4.1.23.5.2.1.5',
            VERSION => '1.3.6.1.4.1.34774.4.1.23.5.2.1.11'
        },

        POOL_LIST => { NAME => '1.3.6.1.4.1.34774.4.1.23.4.2.1.2' },

        # RAID_LIST => {
        #     NAME      => '1.3.6.1.4.1.789.1.5.8.1.2',
        #     TYPE      => '1.3.6.1.4.1.789.1.5.8.1.6',
        #     POOL_NAME => '1.3.6.1.4.1.789.1.5.8.1.9'
        # },
        LUN_LIST => {
            NAME      => '1.3.6.1.4.1.34774.4.1.23.4.8.1.2',
            LUN_ID    => '1.3.6.1.4.1.34774.4.1.23.4.8.1.13',
            CAPACITY  => '1.3.6.1.4.1.34774.4.1.23.4.8.1.5',
            TYPE      => '1.3.6.1.4.1.34774.4.1.23.4.8.1.11',
            POOL_NAME => '1.3.6.1.4.1.34774.4.1.23.4.8.1.4'
        },
        HBA_LIST => {
            NAME => '1.3.6.1.4.1.34774.4.1.23.5.9.1.2',
            WWN  => '1.3.6.1.4.1.34774.4.1.23.5.9.1.8'
        },
        ETH_LIST => {
            NAME => '1.3.6.1.4.1.34774.4.1.23.5.8.1.2',
            MAC  => '1.3.6.1.4.1.34774.4.1.23.5.8.1.12',
            IP   => '1.3.6.1.4.1.34774.4.1.23.5.8.1.6'
        }
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
        $poolInfo->{LUNS} = [];
        $poolsMap->{ $poolInfo->{NAME} } = $poolInfo;
    }

    my $luns = $tableData->{LUN_LIST};
    foreach my $lunInfo (@$luns) {
        my $poolInfo   = $poolsMap->{ $lunInfo->{POOL_NAME} };
        my $lunsInPool = $poolInfo->{LUNS};
        push( @$lunsInPool, $lunInfo );
    }

    my $ctrls     = $tableData->{CTRL_LIST};
    my @ctrlNames = ();
    foreach my $ctrlInfo (@$ctrls) {
        push( @ctrlNames, $ctrlInfo->{NAME} );
    }

    #通过hba卡的名称和控制器名称的关系建立关联
    my $hbas = $tableData->{HBA_LIST};
    foreach my $hbaInfo (@$hbas) {
        my $hbaName = $hbaInfo->{NAME};
        my $wwn     = $hbaInfo->{WWN};
        $wwn =~ s/..\K(?=.)/:/sg;
        $hbaInfo->{WWN} = $wwn;

        foreach my $ctrlName (@ctrlNames) {
            if ( $hbaName =~ /\Q$ctrlName\E/ ) {
                $hbaInfo->{CTROLLER_NAME} = $ctrlName;
                last;
            }

            #下面的判断HBA属于哪个机头的判断主要用户HuaWei18500
            #TODO：需要验证全面性
            elsif ( $hbaName =~ /R0\.IOM0/ and $ctrlName =~ /\.A$/ ) {
                $hbaInfo->{CTROLLER_NAME} = $ctrlName;
                last;
            }
            elsif ( $hbaName =~ /L0\.IOM0/ and $ctrlName =~ /\.B$/ ) {
                $hbaInfo->{CTROLLER_NAME} = $ctrlName;
                last;
            }
            elsif ( $hbaName =~ /R0\.IOM1/ and $ctrlName =~ /\.C$/ ) {
                $hbaInfo->{CTROLLER_NAME} = $ctrlName;
                last;
            }
            elsif ( $hbaName =~ /L0\.IOM1/ and $ctrlName =~ /\.D$/ ) {
                $hbaInfo->{CTROLLER_NAME} = $ctrlName;
                last;
            }
        }
    }

    #通过网卡的名称和控制器名称的关系建立关联
    my $nics = $tableData->{ETH_LIST};
    foreach my $nicInfo (@$nics) {
        my $nicName = $nicInfo->{NAME};

        foreach my $ctrlName (@ctrlNames) {
            if ( $nicName =~ /\Q$ctrlName\E/ ) {
                $nicInfo->{CTROLLER_NAME} = $ctrlName;
                last;
            }

            #下面的判断HBA属于哪个机头的判断主要用户HuaWei18500
            #TODO：需要验证全面性
            elsif ( $nicName =~ /SMM0/ and $ctrlName =~ /\.A$/ ) {
                $nicInfo->{CTROLLER_NAME} = $ctrlName;
                last;
            }
            elsif ( $nicName =~ /SMM1/ and $ctrlName =~ /\.B$/ ) {
                $nicInfo->{CTROLLER_NAME} = $ctrlName;
                last;
            }
        }
    }

    my $data = $self->{DATA};
    $data->{STORAGE_POOLS}  = $pools;
    $data->{CONTROLLERS}    = $tableData->{CTRL_LIST};
    $data->{HBA_INTERFACES} = $tableData->{HBA_LIST};
    $data->{ETH_INTERFACES} = $tableData->{ETH_LIST};

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

