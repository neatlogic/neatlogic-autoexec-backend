#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");

package StorageHDS_VSP;
use strict;

use JSON;
use CollectUtils;

sub new {
    my ( $type, %args ) = @_;
    my $self = {};

    my $cliHome = $args{cliHome};
    if ( not defined($cliHome) or $cliHome == '' ) {
        $cliHome = abs_path("$FindBin::Bin/../../../tools/storage/hds_cci/usr");
    }
    my $path = $ENV{PATH};
    if ( $path !~ /\Q$cliHome\/bin\E/ ) {
        $ENV{PATH} = "$cliHome/bin:$path";
    }

    my $node = $args{node};
    $self->{node} = $node;

    my $timeout = $args{timeout};
    if ( not defined($timeout) or $timeout eq '0' ) {
        $timeout = 10;
    }
    $self->{timeout} = $timeout;
    
    my $host = $node->{host};
    my $user = $node->{username};
    my $pass = $node->{password};

    #TODO: 自动注册存储ID
    my $storageId = 1;                    #TODO：这里的ID根据自动注册来获取ID
    my $self->{storageId} = $storageId;

    my $loginStatus = sytem("raidcom -I$storageId -login '$user' '$pass'");
    if ( $loginStatus ne 0 ) {
        die("ERROR: Login HDS storage:$host by cli failed, $@\n");
    }

    END {
        local $?;
        if ( $loginStatus eq 0 ) {
            system("raidcom -logout -I$storageId");
        }
    }

    my $utils = CollectUtils->new();
    $self->{collectUtils} = $utils;

    bless( $self, $type );
    return $self;
}

sub collect {
    my ($self) = @_;
    my $data = {};

    $data->{VENDOR} = 'HDS';
    $data->{BRAND}  = 'VSP';

    my $nodeInfo  = $self->{node};
    my $utils     = $self->{collectUtils};
    my $storageId = $self->{storageId};

    #RS_GROUP            RGID   V_Serial#  V_ID   V_IF    Serial#
    #meta_resource          0      412905  M8H    Y        412905
    my $devInfoLines = $utils->getCmdOutLines("raidcom get resource -key opt -I$storageId");
    my @splits       = split( /\s+/, $$devInfoLines[-1] );
    my $SN           = $splits[2];
    $data->{SN} = $SN;

    my $storageType    = $splits[3];
    my $storageTypeMap = {
        M8S     => 'VSP G200',
        M800S   => 'VSP G200',
        M8M     => 'VSP G400/G600 or F400/F600',
        M800M   => 'VSP G400/G600 or F400/F600',
        M8H     => 'VSP G/F800',
        M800H   => 'VSP G/F800',
        M850S1  => 'VSP G350',
        M850S1F => 'VSP F350',
        M850S2  => 'VSP G370',
        M850S2F => 'F370',
        M850M3  => 'G700',
        M850M3F => 'VSP F700',
        M850H   => 'VSP G900',
        M850HF  => 'VSP F900',
        R8      => 'VSP G/F1x00 or HPE XP7',
        R800    => 'VSP G/F1x00 or HPE XP7',
        M7      => 'HUS VM',
        M700    => 'HUS VM',
        R7      => 'VSP or HPE XP P9500',
        R700    => 'VSP or HPE XP P9500',
        R6      => 'USP V',
        R600    => 'USP V',
        RK6     => 'USP VM',
        RK600   => 'USP VM',
        R5      => 'TagmaStore USP',
        R500    => 'TagmaStore USP',
        RK5     => 'TagmaStore NSC',
        RK500   => 'TagmaStore NSC'
    };
    $storageType = $storageTypeMap->{$storageType};
    $data->{MODEL} = $storageType;

    my @luns = ();
    my @pools = ();
    my $poolInfoLines = $utils->getCmdOutLines("raidcom get pool -I$storageId");
    for ( my $i = 0 ; $i < scalar(@$poolInfoLines) ; $i++ ) {
        my $line = $$poolInfoLines[$i];
        $line =~ s/^\s+|\s+$//g;

        my $poolInfo = {};
        my $poolName = ( split( /\s+/, $line ) )[0];
        $poolInfo->{NAME} = $poolName;

        my @lunsInPool;
        my $lunInPoolInfo = $utils->getCmdOut("raidcom get ldev -ldev_list defined -pool_id $poolName -I$storageId");
        while ( $$lunInPoolInfo =~ /LDEV.*?(?=STS)/sg ) {
            my $line    = $&;    #match content
                                 #$line =~ s/^\s+|\s+$//g;
            my $lunInfo = {};

            my $name;
            my $lunId;
            my $capacity;
            if ( $line =~ /VOL_Capacity\(BLK\)\s+:\s+(\d+)/ ) {
                $capacity = int( $1 * 100 / 1024 / 1024 + 0.5 ) / 100;
            }
            if ( $line =~ /LDEV\s+:\s+(\d+)/ ) {
                $lunId = $1;
            }
            if ( $line =~ /LDEV_NAMING\s+:\s+(\w+)/ ) {
                $name = $1;
            }
            else {
                $name = '';
            }
            $lunInfo->{NAME}      = $name;
            $lunInfo->{LUN_ID}    = $lunId;
            $lunInfo->{CAPACITY}  = $capacity;
            $lunInfo->{POOL_NAME} = $poolName;

            push( @lunsInPool, $lunInfo );
            push( @luns, $lunInfo );
        }
        $poolInfo->{LUNS} = \@lunsInPool;
        push( @pools, $poolInfo );
    }

    my $hbasMap      = {};
    my $hbaInfoLines = $utils->getCmdOutLines("raidcom get port -I$storageId");
    foreach my $line (@$hbaInfoLines) {
        $line =~ s/^\s+|\s+$//g;
        my @splits = split( /\s+/, $line );
        my $name   = $splits[0];
        my $wwn    = $splits[10];
        $hbasMap->{$name} = $wwn;
    }

    my @ctrollers;
    my $ctrlInfoLines = $utils->getCmdOutLines("raidcom get port -I$storageId | awk 'NR>1' | awk -F - '{print \$1}' | uniq");
    foreach my $ctrlName (@$ctrlInfoLines) {
        chomp($ctrlName);

        my $ctrlInfo = {};
        $ctrlInfo->{NAME} = $ctrlName;

        my @hbas = ();
        foreach my $hbaName ( keys(%$hbasMap) ) {
            if ( $hbaName =~ /\Q$ctrlName\E/ ) {
                my $wwn = $hbasMap->{$hbaName};
                $wwn =~ s/..\K(?=.)/:/sg;
                my $hbaInfo = {};
                $hbaInfo->{NAME} = $hbaName;
                $hbaInfo->{WWN}  = $wwn;

                push( @hbas, $hbaInfo );
            }
        }

        $ctrlInfo->{HBA_INTEFACES} = \@hbas;
        push( @ctrollers, $ctrlInfo );
    }

    $data->{CONTROLLERS}   = \@ctrollers;
    $data->{POOLS} = \@pools;
    $data->{LUNS}  = \@luns;

    return $data;
}

1;

