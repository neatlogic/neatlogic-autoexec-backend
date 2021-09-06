#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");

package StorageIBM_V7000;
use strict;

use Net::OpenSSH;
use JSON;
use CollectUtils;

sub new {
    my ( $type, %args ) = @_;
    my $self = {};

    my $node = $args{node};
    $self->{node} = $node;

    my $utils = CollectUtils->new();
    $self->{collectUtils} = $utils;

    bless( $self, $type );
    return $self;
}

sub collect {
    my ($self) = @_;
    my $data = {};

    $data->{VENDOR} = 'IBM';
    $data->{BRAND}  = 'IBM';

    my $nodeInfo = $self->{node};

    my $sshclient = Net::OpenSSH->new(
        $nodeInfo->{host},
        port        => $nodeInfo->{port},
        user        => $nodeInfo->{username},
        password    => $nodeInfo->{password},
        timeout     => 10,
        master_opts => [ -o => "StrictHostKeyChecking=no" ]
    );

    if ( $sshclient->error ) {
        die( "ERROR: Can not establish SSH connection: " . $sshclient->error );
    }

    ######################################################
    my @storageInfoLines = $sshclient->capture("lssystem -delim :");
    foreach my $line (@storageInfoLines) {
        if ( $line =~ /^id:(.*?)\s*$/ ) {
            $data->{SN} = $1;
        }
        if ( $line =~ /^name:(.*?)\s*$/ ) {
            $data->{DEV_NAME} = $1;
        }
        if ( $line =~ /^total_drive_raw_capacity:(.*?)\s*$/ ) {
            $data->{CAPACITY} = $1 + 0.0;    #Unit TB
        }
    }

    my @fcPorts     = ();
    my @fcInfoLines = $sshclient->capture("lsportfc -delim :");
    for ( my $i = 1 ; $i <= $#fcInfoLines ; $i++ ) {
        my $line = $fcInfoLines[$i];
        if ( $line =~ /\d+?:\d+?:\d+?:(\S+?):(\S+?):\d+?:\S+?:(\S+?):\S+?:(\S+?):(\S+)/ ) {
            if ( ( $1 eq 'fc' ) && ( $4 eq 'active' ) && ( $5 eq 'switch' ) ) {
                my $fcInfo = {};
                $fcInfo->{WWN}   = $3;
                $fcInfo->{SPEED} = $2;
                push( @fcPorts, $fcInfo );
            }
        }
    }
    $data->{FC_PORTS} = \@fcPorts;

    #网络端口MAC地址信息
    my @macAddrs     = ();
    my $macsMap      = {};
    my @macInfoLines = $sshclient->capture("lsportip -delim [");
    for ( my $i = 0 ; $i <= $#macInfoLines ; $i++ ) {
        my $line = $macInfoLines[$i];
        chomp($line);
        my @tmp = split( /\[/, $line );
        my $macAddr = $tmp[9];
        if ( not defined( $macsMap->{$macAddr} ) ) {
            $macsMap->{ $tmp[9] } = 1;
            push( @macAddrs, { VALUE => $macAddr } );
        }
    }
    $data->{MAC_ADDRS} = \@macAddrs;

    #raid信息
    my $poolRaidGroups = {};
    my @raidGroups     = ();
    my $raidName2Obj   = {};
    my @raidInfoLines  = $sshclient->capture("lsarray -delim :");
    for ( my $i = 0 ; $i <= $#raidInfoLines ; $i++ ) {
        my $line = $raidInfoLines[$i];
        if ( $line =~ /\d+?:(\S+?):\S+?:\d+?:(\S+?):\S+?:\S+?:(\S+?):/ ) {
            my $raidName = $1;
            my $poolName = $2;
            my $raidType = $3;

            my $raidInfo = {};
            $raidInfo->{NAME}      = $raidName;
            $raidInfo->{TYPE}      = $raidType;
            $raidInfo->{DISKS}     = [];
            $raidInfo->{POOL_NAME} = $poolName;
            push( @raidGroups, $raidInfo );
            $raidName2Obj->{$raidName} = $raidInfo;

            #记录raid组和pool name的关系
            my $raidGroupInPool = $poolRaidGroups->{$poolName};
            if ( not defined($raidGroupInPool) ) {
                $raidGroupInPool = [];
                $poolRaidGroups->{$poolName} = $raidGroupInPool;
            }
            push( @$raidGroupInPool, $raidInfo );
        }
    }
    $data->{RAID_GROUPS} = \@raidGroups;

    #disk信息
    my @disks;
    my @disk2raidInfoLines = $sshclient->capture("lsdrive -delim [");
    for ( my $i = 0 ; $i <= $#disk2raidInfoLines ; $i++ ) {
        my $line = $disk2raidInfoLines[$i];
        chomp($line);
        my @tmp = split( /\[/, $line );

        my $diskInfo = {};
        $diskInfo->{CAPACITY} = $tmp[5];
        my $typeInfo = $tmp[4];
        if ( $typeInfo =~ /hdd/i ) {
            $diskInfo->{TYPE} = 'HDD';
        }
        elsif ( $typeInfo =~ /ssd/i ) {
            $diskInfo->{TYPE} = 'SSD';
        }

        my $enclosureId = $tmp[9];
        my $slotId      = $tmp[10];
        $diskInfo->{POSITION} = "${enclosureId}_${slotId}";

        my $raidName = $tmp[7];
        $diskInfo->{RAID_NAME} = $raidName;
        push( @disks, $diskInfo );

        #记录disk和raid group的关系
        my $raidInfo = $raidName2Obj->{$raidName};
        if ( defined($raidInfo) ) {
            my $diskInRaidGroup = $raidInfo->{DISKS};
            push( @$diskInRaidGroup, $diskInfo );
        }
    }
    $data->{DISKS} = \@disks;

    ############################################################
    #lun信息
    my $poolLuns     = {};
    my @luns         = ();
    my @lunInfoLines = $sshclient->capture("lsvdisk -delim :");
    for ( my $i = 0 ; $i <= $#lunInfoLines ; $i++ ) {
        my $line = $lunInfoLines[$i];
        $line =~ s/^\s+|\s+$//;
        my @tmp = split( /:/, $line );
        my $lunInfo = {};
        $lunInfo->{LUNID}    = $tmp[-13];
        $lunInfo->{NAME}     = $tmp[1];
        $lunInfo->{CAPACITY} = $tmp[7];

        my $poolName = $tmp[6];
        $lunInfo->{POOL_NAME} = $poolName;
        push( @luns, $lunInfo );

        my $lunsInPool = $poolLuns->{$poolName};
        if ( not defined($lunsInPool) ) {
            $lunsInPool = [];
            $poolLuns->{$poolName} = $lunsInPool;
        }
        push( @$lunsInPool, $lunInfo );
    }
    $data->{LUNS} = \@luns;

    #############################################
    #pool信息
    my @pools         = ();
    my @poolInfoLines = $sshclient->capture("lsmdiskgrp -delim :");
    for ( my $i = 0 ; $i <= $#poolInfoLines ; $i++ ) {
        my $line = $poolInfoLines[$i];
        chomp($line);

        my $poolName;
        my $poolInfo = {};
        if ( $line =~ /\d+?:(\S+?):/ ) {
            $poolName = $1;
        }

        $poolInfo->{NAME} = $poolName;
        my $raidGroups = $poolRaidGroups->{$poolName};
        $poolInfo->{RAID_GROUPS} = $raidGroups;
        $poolInfo->{LUNS}        = $poolLuns->{$poolName};

        #计算pool下所有的disks，用于没有Raid组这一层的存储设备
        # my @disksInPool = ();
        # foreach my $raidInfo (@$raidGroups){
        #     my $disksInRaid = $raidInfo->{DISKS};
        #     push(@disksInPool, @$disksInRaid);
        # }
        # $poolInfo->{DISKS} = \@disksInPool;

        push( @pools, $poolInfo );
    }
    $data->{POOLS} = \@pools;
    $sshclient->disconnect();

    return $data;
}

1;

