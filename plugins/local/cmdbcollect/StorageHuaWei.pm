#!/usr/bin/perl
use strict;
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");

package StorageHuawei;

use StorageBase;
our @ISA = qw(StorageBase);

use JSON;
use Data::Dumper;

sub before {
    my ($self) = @_;
    $self->addScalarOid(
        SN            => ['1.3.6.1.4.1.34774.4.1.1.1'],    #deviceId
        VERSION       => '1.3.6.1.4.1.34774.4.1.1.6',      #Version
        GLOBAL_STATUS => '1.3.6.1.4.1.34774.4.1.1.3'       #status
    );

    $self->addTableOid(
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
            WWN       => '1.3.6.1.4.1.34774.4.1.23.4.8.1.13',
            CAPACITY  => '1.3.6.1.4.1.34774.4.1.23.4.8.1.5',
            TYPE      => '1.3.6.1.4.1.34774.4.1.23.4.8.1.11',
            POOL_NAME => '1.3.6.1.4.1.34774.4.1.23.4.8.1.4'
        },
        HBA_LIST => {
            NAME => '1.3.6.1.4.1.34774.4.1.23.5.9.1.2',
            WWPN => '1.3.6.1.4.1.34774.4.1.23.5.9.1.8'
        },
        ETH_LIST => {
            NAME => '1.3.6.1.4.1.34774.4.1.23.5.8.1.2',
            MAC  => '1.3.6.1.4.1.34774.4.1.23.5.8.1.12',
            IP   => '1.3.6.1.4.1.34774.4.1.23.5.8.1.6'
        }
    );
}

sub after {
    my ($self) = @_;

    $self->getPools();

    my $data = $self->{DATA};
    $data->{VENDOR} = 'Huawei';
    $data->{BRAND}  = 'Huawei';

    return;
}

#get table values from 1 or more than table oid
sub getPools {
    my ($self) = @_;
    my $tableData = $self->{DATA};

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
        my $wwpn    = $hbaInfo->{WWPN};
        $wwpn =~ s/..\K(?=.)/:/sg;
        $hbaInfo->{WWPN} = $wwpn;

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

    foreach my $oldKey ( 'POOL_LIST', 'LUN_LIST' ) {
        delete( $tableData->{$oldKey} );
    }

    $data->{POOLS}          = $pools;
    $data->{LUNS}           = $luns;
    $data->{CONTROLLERS}    = $tableData->{CTRL_LIST};
    $data->{HBA_INTERFACES} = $tableData->{HBA_LIST};
    $data->{ETH_INTERFACES} = $tableData->{ETH_LIST};

    foreach my $oldKey ( 'CTRL_LIST', 'HBA_LIST', 'ETH_LIST' ) {
        delete( $data->{$oldKey} );
    }

    return;
}

1;

