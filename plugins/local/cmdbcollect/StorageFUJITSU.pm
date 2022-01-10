#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");

package StorageFUJITSU;
use strict;

use Net::OpenSSH;
use JSON;
use CollectUtils;

sub new {
    my ( $type, %args ) = @_;
    my $self = {};

    my $node = $args{node};
    $self->{node} = $node;

    my $timeout = $args{timeout};
    if ( not defined($timeout) or $timeout eq '0' ) {
        $timeout = 10;
    }
    $self->{timeout} = $timeout;

    my $utils = CollectUtils->new();
    $self->{collectUtils} = $utils;

    bless( $self, $type );
    return $self;
}

sub collect {
    my ($self) = @_;
    my $data = {};
    $data->{VENDOR} = 'FUJITSU';
    $data->{BRAND}  = 'FUJITSU';

    my $nodeInfo = $self->{node};

    my $ssh = Net::OpenSSH->new(
        $nodeInfo->{host},
        port        => $nodeInfo->{protocolPort},
        user        => $nodeInfo->{username},
        password    => $nodeInfo->{password},
        timeout     => $self->{timeout},
        master_opts => [ -o => "StrictHostKeyChecking=no" ]
    );
    if ( $ssh->error ){
        print("ERROR: Cound not connect to $nodeInfo->{host}, " . $ssh->error);
        exit(-1);
    }

    my $sysInfo = $ssh->capture('show storage-system-name');
    if ( $sysInfo =~ /Name\s*\[(.*?)\]\s+/ ) {
        $data->{MODEL} = $1;
    }

    my $sn;
    my $snInfo = $ssh->capture('show hardware-information');
    if ( $snInfo =~ /Controller Enclosure\s*(.*?)\s+/ ) {
        $sn = $1;
    }
    $data->{SN} = $sn;

    #Volume: LUN
    #第4、5字段是RAID_GROUP或者Thin Provision Pool或Flexible Tier Pool
    #RAID group identifiers, External RAID Group identifiers, Thin Provisioning Pool identifiers, or Flexible Tier Pool identifiers
    # CLI> show volumes -csv
    # [Volume No.],[Volume Name],[Status],[Type],[RG or TPP or FTRP No.],[RG or TPP or FTRP Name],[Size(MB)],[Copy Protection]
    # 0,OLU#0,Available,Standard,0,RLU#0,256,Disable
    # 1,OLU#1,Available,Standard,0,RLU#0,256,Disable
    # 2,OLU#2,Available,Standard,0,RLU#0,256,Disable
    # 7,TPV#1,Available,TPV,1,TPP#1,256,Disable
    # 8,TPV#2,Available,TPV,1,TPP#1,256,Disable
    my $poolLunsMap = {};
    my $lunIdsMap   = {};
    my @luns;
    my @lunInfoLines = $ssh->capture('show volumes -csv');
    for ( my $i = 1 ; $i < $#lunInfoLines ; $i++ ) {
        my $line = $lunInfoLines[$i];

        $line =~ s/^\s+|\s+$//g;
        my @splits = split( /,/, $line );
        my $id     = $splits[0];
        my $poolId = $splits[4];

        my $lunInfo = {};
        $lunInfo->{ID}   = $id;
        $lunInfo->{NAME} = $splits[1];

        #$lunInfo->{WWID}    = undef;
        $lunInfo->{TYPE}      = $splits[3];
        $lunInfo->{POOL_ID}   = $poolId;
        $lunInfo->{POOL_NAME} = $splits[5];
        $lunInfo->{CAPACITY}  = int( $splits[6] * 100 / 1024 + 0.5 ) / 100;

        $lunIdsMap->{$id} = $lunInfo;
        push( @luns, $lunInfo );

        my $lunsInPool = $poolLunsMap->{$poolId};
        if ( not defined($lunsInPool) ) {
            $lunsInPool = [];
            $poolLunsMap->{$poolId} = $lunsInPool;
        }

        push( @$lunsInPool, $lunInfo );
    }

    # CLI> show volume-mapping -volume-number 0
    # Volume Type UID
    # No. Name
    # ----- -------------------------------- --------- --------------------------------
    # 0 OLU#0 Standard 600000E00D2A0000002A000000000000
    # <Mapping>
    # LUN LUN Group Port
    # No. Name
    # ---- ---- ---------------- ---------------------
    # 10 0 AG001 -
    # 0 - - CM#0 CA#0 Port#0
    # 0 - - CM#1 CA#0 Port#0
    # 0 - - CM#1 CA#0 Port#1
    my @lunIdInfoLines = $ssh->capture('show volume-mapping');
    for ( my $i = 3 ; $i < $#lunIdInfoLines ; $i++ ) {
        my $line = $lunIdInfoLines[$i];
        if ( $line =~ /^<Mapping>\s*$/ ) {
            last;
        }
        $line =~ s/^\s*|\s*$//g;
        my @splits = split( /\s+/, $line );
        my $id     = $splits[0];
        my $lunId  = $splits[-1];

        my $lunInfo = $lunIdsMap->{$id};
        if ( defined($lunInfo) ) {
            $lunInfo->{WWID} = $lunId;
        }
    }

    # CLI> show raid-groups -csv
    # [RAID Group No.],[RAID Group Name],[RAID Level],[Assigned CM],[Status],[Total Capacity(MB)],[Free Capacity(MB)]
    # 1,RAIDGROUP001,RAID1+0,CM#0,Spare in Use,134656,132535
    # 2,RAIDGROUP002,RAID5,CM#1,Available,134656,132532
    # 3,RAIDGROUP003,RAID5,CM#1,SED Locked,134656,132532
    my @raidGroups         = ();
    my @raidGroupInfoLines = $ssh->capture('show raid-groups -csv');
    for ( my $i = 1 ; $i < $#raidGroupInfoLines ; $i++ ) {
        my $line = $raidGroupInfoLines[$i];
        $line =~ s/^\s*|\s*$//g;
        my @splits = split( /,/, $line );
        my $rgNo = $splits[0];

        my $size = ( $splits[5] * 100 / 1024 + 0.5 ) / 100;
        my $free = ( $splits[6] * 100 / 1024 + 0.5 ) / 100;

        my $rgInfo = {};
        $rgInfo->{ID}           = $rgNo;
        $rgInfo->{NAME}         = $splits[1];
        $rgInfo->{LEVEL}        = $splits[2];
        $rgInfo->{STATUS}       = $splits[4];
        $rgInfo->{CAPACITY}     = $size;
        $rgInfo->{FREE}         = $free;
        $rgInfo->{USED}         = $size - $free;
        $rgInfo->{USED_PERCENT} = int( ( $size - $free ) * 10000 / $size * 0.5 ) / 100;
        $rgInfo->{LUNS}         = $poolLunsMap->{$rgNo};

        push( @raidGroups, $rgInfo );
    }

    #富士通的存储LUN（Volume）挂在RAID Group下，
    $data->{RAID_GROUPS} = \@raidGroups;

    # CLI> show thin-pro-pools -pool-number 1,2,4 –sort used-capacity -order ascending –csv
    # [Pool No],[Pool Name],[Status],[Used Status],[Total Capacity(MB)],[Used Capacity(MB)],[Used Rate(%)],[Provisioned Capacity(MB)],[Provisioned
    # Rate(%)],[Warning(%)],[Attention(%)],[Compression],[Data Size Before Reduction(MB)],[Data Size After Reduction(MB)],[Data Reduction
    # Rate(%)],[GC Speed(MB/s)],[Number of Volumes],[Encryption],[Chunk Size(MB)],[Disk Attribute],[RAID Level],[Deduplication],[GC Remaining
    # Size(MB)]
    # 1,TPP01,Available,Normal,279029,12000,5,139000,-,90,75,Enable,1058,952,10,0,8,Disable,21,Online,RAID1,Disable,20480
    # 4,TPP04,Available,Normal,279029,12000,5,139000,-,90,75,Enable,1058,952,10,0,8,Disable,21,Online,RAID1,Disable,20480
    # 2,TPP02,Available,Normal,279029,102400,37,139000,49,90,75,Disable,-,-,-,-,8,Disable,21,Online,RAID1,Disable,-
    my @pools         = ();
    my @poolInfoLines = $ssh->capture('show thin-pro-pools -csv');
    for ( my $i = 1 ; $i < $#poolInfoLines ; $i++ ) {
        my $line = $poolInfoLines[$i];
        $line =~ s/^\s*|\s*$//g;
        my @splits = split( /,/, $line );
        my $poolNo = $splits[0];

        my $poolInfo = {};
        $poolInfo->{ID}                   = $poolNo;
        $poolInfo->{NAME}                 = $splits[1];
        $poolInfo->{TYPE}                 = 'TPP';
        $poolInfo->{STATUS}               = $splits[2];
        $poolInfo->{CAPACITY}             = ( $splits[4] * 100 / 1024 + 0.5 ) / 100;
        $poolInfo->{USED}                 = ( $splits[5] * 100 / 1024 + 0.5 ) / 100;
        $poolInfo->{FREE}                 = $poolInfo->{CAPACITY} - $poolInfo->{USED};
        $poolInfo->{USED_PERCENT}         = $splits[6] + 0;
        $poolInfo->{PROVISIONED_CAPACITY} = ( $splits[7] * 100 / 1024 + 0.5 ) / 100;
        $poolInfo->{PROVISIONED_PERCENT}  = ( $splits[8] * 100 / 1024 + 0.5 ) / 100;
        $poolInfo->{LUNS}                 = $poolLunsMap->{$poolNo};

        push( @pools, $poolInfo );
    }

    # CLI> show flexible-tier-pools
    # Flexible Tier Pool Status Used Total Used Provisioned
    # No. Name Status Capacity Capacity Rate(%) Capacity Rate(%)
    # --- ---------------- ------------- --------- ---------- ---------- ------- ----------- -------
    # 0 FTRP_NAME#0 Available Normal 20.02 GB 1.03 GB 20 4.02 GB 20
    my @poolInfoLines = $ssh->capture('show flexible-tier-pools -csv');
    for ( my $i = 1 ; $i < $#poolInfoLines ; $i++ ) {
        my $line = $poolInfoLines[$i];
        $line =~ s/^\s*|\s*$//g;
        my @splits = split( /,/, $line );
        my $poolNo = $splits[0];

        my $poolInfo = {};
        $poolInfo->{ID}                   = $poolNo;
        $poolInfo->{NAME}                 = $splits[1];
        $poolInfo->{TYPE}                 = 'FTRP';
        $poolInfo->{STATUS}               = $splits[2];
        $poolInfo->{CAPACITY}             = ( $splits[4] * 100 / 1024 + 0.5 ) / 100;
        $poolInfo->{USED}                 = ( $splits[5] * 100 / 1024 + 0.5 ) / 100;
        $poolInfo->{FREE}                 = $poolInfo->{CAPACITY} - $poolInfo->{USED};
        $poolInfo->{USED_PERCENT}         = $splits[6] + 0;
        $poolInfo->{PROVISIONED_CAPACITY} = ( $splits[7] * 100 / 1024 + 0.5 ) / 100;
        $poolInfo->{PROVISIONED_PERCENT}  = ( $splits[8] * 100 / 1024 + 0.5 ) / 100;
        $poolInfo->{LUNS}                 = $poolLunsMap->{$poolNo};

        push( @pools, $poolInfo );
    }

    $data->{POOLS} = \@pools;
    $data->{LUNS}  = \@luns;

    $ssh->disconnect();
    return $data;
}

1;

