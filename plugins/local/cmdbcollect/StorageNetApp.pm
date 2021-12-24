#!/usr/bin/perl
use strict;
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");

package StorageNetApp;

use StorageBase;
our @ISA = qw(StorageBase);

use JSON;
use Data::Dumper;

sub before {
    my ($self) = @_;
    $self->addScalarOid(
        CPU_USAGE                 => '1.3.6.1.4.1.789.1.2.1.3.0',    #cpuBusyTimePerCent
        MODEL                     => '1.3.6.1.4.1.789.1.1.5.0',      #productModel
        SN                        => ['1.3.6.1.4.1.789.1.1.9.0'],    #productSerialNum
        PRODUCT_TYPE              => '1.3.6.1.4.1.789.1.1.1.0',      #productType
        PRODUCT_VERSION           => '1.3.6.1.4.1.789.1.1.2.0',      #productVersion
        OVER_TEMPERATURE          => '1.3.6.1.4.1.789.1.2.4.1.0',    #envOverTemperature no(1), yes(2)
        FAILED_FAN_COUNT          => '1.3.6.1.4.1.789.1.2.4.2.0',    #envFailedFanCount
        FAILED_POWER_SUPPLY_COUNT => '1.3.6.1.4.1.789.1.2.4.4.0',    #envFailedPowerSupplyCount
        GLOBAL_STATUS             => '1.3.6.1.4.1.789.1.2.2.4.0'     #miscGlobalStatus other(1),unknown(2),ok(3),nonCritical(4),critical(5),nonRecoverable(6)
    );

    $self->addTableOid(
        AGGR_LIST => {
            NAME      => '1.3.6.1.4.1.789.1.5.11.1.2',
            RAID_TYPE => '1.3.6.1.4.1.789.1.5.11.1.11'
        },
        VOL_LIST => {
            NAME      => '1.3.6.1.4.1.789.1.5.8.1.2',
            TYPE      => '1.3.6.1.4.1.789.1.5.8.1.6',
            AGGR_NAME => '1.3.6.1.4.1.789.1.5.8.1.9'
        },
        QTREE_LIST => {
            NAME     => '1.3.6.1.4.1.789.1.5.10.1.5',
            ID       => '1.3.6.1.4.1.789.1.5.10.1.4',
            VOL_NAME => '1.3.6.1.4.1.789.1.5.10.1.3'
        },
        LUN_LIST => {
            NAME       => '1.3.6.1.4.1.789.1.17.15.2.1.2',
            WWID       => '1.3.6.1.4.1.789.1.17.15.2.1.7',
            CAPACITY   => '1.3.6.1.4.1.789.1.17.15.2.1.28',
            QTREE_NAME => '1.3.6.1.4.1.789.1.17.15.2.1.8'
        },
        HBA_LIST   => { WWN => '1.3.6.1.4.1.789.1.17.16.2.1.3' },
        DF_VOLUMES => {
            NAME               => '1.3.6.1.4.1.789.1.5.4.1.2',
            MOUNT_ON           => '1.3.6.1.4.1.789.1.5.4.1.10',
            CAPACITY           => '1.3.6.1.4.1.789.1.5.4.1.29',
            USED               => '1.3.6.1.4.1.789.1.5.4.1.30',
            FREE               => '1.3.6.1.4.1.789.1.5.4.1.31',
            USED_PERCENT       => '1.3.6.1.4.1.789.1.5.4.1.6',
            INODE_USED         => '1.3.6.1.4.1.789.1.5.4.1.7',
            INODE_FREE         => '1.3.6.1.4.1.789.1.5.4.1.8',
            USED_INODE_PERCENT => '1.3.6.1.4.1.789.1.5.4.1.9'
        }
    );
}

sub after {
    my ($self) = @_;

    $self->getPools();

    my $data = $self->{DATA};
    $data->{VENDOR} = 'NetApp';
    $data->{BRAND}  = 'NetApp';
    
    return;
}

#get table values from 1 or more than table oid
sub getPools {
    my ($self) = @_;
    my $tableData = $self->{DATA};

    my $aggrs    = $tableData->{AGGR_LIST};
    my $aggrsMap = {};
    foreach my $aggrInfo (@$aggrs) {
        $aggrInfo->{VOLUMES} = [];
        $aggrsMap->{ $aggrInfo->{NAME} } = $aggrInfo;
    }

    my $vols      = $tableData->{VOL_LIST};
    my $volsMap   = {};
    my $volIdxMap = {};
    foreach my $volInfo (@$vols) {
        $volInfo->{QTREES}                = [];
        $volsMap->{ $volInfo->{NAME} }    = $volInfo;
        $volIdxMap->{ $volInfo->{INDEX} } = $volInfo;
        my $aggrInfo   = $aggrsMap->{ $volInfo->{AGGR_NAME} };
        my $volsInAggr = $aggrInfo->{VOLUMES};
        push( @$volsInAggr, $volInfo );
    }

    my $qtrees    = $tableData->{QTREE_LIST};
    my $qtreesMap = {};
    foreach my $qtreeInfo (@$qtrees) {
        $qtreeInfo->{LUNS} = [];
        $qtreesMap->{ $qtreeInfo->{NAME} } = $qtreeInfo;
        my $volInfo     = $volsMap->{ $qtreeInfo->{VOL_NAME} };
        my $qtreesInVol = $volInfo->{QTREES};
        push( @$qtreesInVol, $qtreeInfo );
    }

    my $luns = $tableData->{LUN_LIST};
    foreach my $lunInfo (@$luns) {
        $lunInfo->{CAPACITY} = int( $lunInfo->{CAPACITY} * 100 / 1024 / 1024 / 1024 + 0.5 ) / 100;

        #Netapp的WWID是一个ascii编码的字串，需要转换，还要加上NetApp的前缀：60a98000
        my $wwId = $lunInfo->{WWID};
        $wwId =~ s/(.)/sprintf "%02x", ord $1/seg;
        $wwId = '60a98000' . $wwId;
        $lunInfo->{WWID} = $wwId;
        my $qtreeInfo   = $qtreesMap->{ $lunInfo->{QTREE_NAME} };
        my $lunsInQtree = $qtreeInfo->{LUNS};
        push( @$lunsInQtree, $lunInfo );
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

    my @validDfVolumes = ();
    my $dfVolumes      = $tableData->{DF_VOLUMES};
    foreach my $dfVolInfo (@$dfVolumes) {
        my $dfName = $dfVolInfo->{NAME};
        if ( $dfName eq '' ) {
            $dfName = '/vol/' . $volIdxMap->{ $dfVolInfo->{INDEX} };
        }

        $dfVolInfo->{CAPACITY} = int( $dfVolInfo->{CAPACITY} * 100 / 1024 / 1024 + 0.5 ) / 100;
        $dfVolInfo->{USED}     = int( $dfVolInfo->{USED} * 100 / 1024 / 1024 + 0.5 ) / 100;
        $dfVolInfo->{FREE}     = int( $dfVolInfo->{FREE} * 100 / 1024 / 1024 + 0.5 ) / 100;

        if ( $dfName ne '' and $dfName =~ /\/vol\// ) {
            push( @validDfVolumes, $dfVolInfo );
        }
    }
    my $data = $self->{DATA};
    
    foreach my $oldKey ( 'AGGR_LIST', 'VOL_LIST', 'QTREE_LIST', 'LUN_LIST', 'HBA_LIST', 'DF_VOLUMES' ) {
        delete( $data->{$oldKey} );
    }

    $data->{STORAGE_AGGRS} = $aggrs;
    $data->{LUNS}          = $luns;
    $data->{VOLUMES}       = $vols;
    $data->{DF_VOLUMES}    = \@validDfVolumes;

    return;
}

1;

