#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");

package StorageIBM_F900;
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

    my $nodeInfo = $self->{node};

    my $ssh = Net::OpenSSH->new(
        $nodeInfo->{host},
        port        => $nodeInfo->{protocolPort},
        user        => $nodeInfo->{username},
        password    => $nodeInfo->{password},
        timeout     => 10,
        master_opts => [ -o => "StrictHostKeyChecking=no" ]
    );

    my $sysInfo = $ssh->capture('lssystem -delim :');
    if ( $sysInfo =~ /product_name:(.*)\n/ ) {
        $data->{MODEL} = $1;
    }
    my $snInfo = $ssh->capture('lsenclosure -delim : -nohdr');
    my $sn = ( split( /:/, $snInfo ) )[4];
    $data->{SN} = $sn;

    #lun
    my $poolLunsMap = {};
    my @luns;
    my @lunInfoLines = $ssh->capture('svcinfo lsvdisk -unit gb -delim : -nohdr');
    foreach my $line (@lunInfoLines) {
        $line =~ s/^\s+|\s+$//g;
        my @splits   = split( /:/, $line );
        my $name     = $splits[1];
        my $lunId    = $splits[4];
        my $poolName = $splits[-1];
        my $capacity = $splits[3];

        my $lunInfo = {};
        $lunInfo->{NAME}      = $name;
        $lunInfo->{LUNID}     = $lunId;
        $lunInfo->{POOL_NAME} = $poolName;
        $lunInfo->{CAPACITY}  = $capacity;
        push( @luns, $lunInfo );

        my $lunsInPool = $poolLunsMap->{$poolName};
        if ( not defined($lunsInPool) ) {
            $lunsInPool = [];
            $poolLunsMap->{$poolName} = $lunsInPool;
        }
        push( @$lunsInPool, $lunInfo );
    }

    #pool and lun
    my @pools;
    my @poolInfoLines = $ssh->capture('svcinfo lsmdiskgrp -nohdr');
    foreach my $line (@poolInfoLines) {
        $line =~ s/^\s+|\s+$//g;
        my $poolName = ( split( /\s+/, $line ) )[1];

        my $poolInfo = {};
        $poolInfo->{NAME} = $poolName;
        $poolInfo->{LUNS} = $poolLunsMap->{$poolName};
        push( @pools, $poolInfo );
    }

    my $ctrlNicsMap = {};
    my @nics;
    my @nicInfLines = $ssh->capture("svcinfo lsportip -delim , -nohdr");
    foreach my $line (@nicInfLines) {
        my @splits   = split( /,/, $line );
        my $name     = $splits[0];
        my $ip       = $splits[6];
        my $mac      = $splits[12];
        my $ctrlName = $splits[2];

        my $nicInfo = {};
        $nicInfo->{NAME} = $name;
        $nicInfo->{MAC}  = $mac;
        $nicInfo->{IP}   = $ip;
        push( @nics, $nicInfo );

        my $ctrlNics = $ctrlNicsMap->{$ctrlName};
        if ( not defined($ctrlNics) ) {
            $ctrlNics = [];
            $ctrlNicsMap->{$ctrlName} = $ctrlNics;
        }
        push( @$ctrlNics, $nicInfo );
    }

    my $ctrlHbasMap = {};
    my @hbas;
    my @hbaInfoLines = $ssh->capture('svcinfo lsportfc -delim : -nohdr');
    foreach my $line (@hbaInfoLines) {
        $line =~ s/^\s+|\s+$//g;
        my @splits = split( /:/, $line );
        my $speed  = $splits[4];
        my $name   = $splits[0] . ':' . $splits[1] . ':' . $splits[2];
        my $wwn    = $splits[7];
        $wwn =~ s/..\K(?=.)/:/sg;
        my $ctrlName = $splits[6];

        my $hbaInfo = {};
        $hbaInfo->{NAME}  = $name;
        $hbaInfo->{SPEED} = $speed;
        $hbaInfo->{WWN}   = $wwn;

        push( @hbas, $hbaInfo );

        my $ctrlHbas = $ctrlHbasMap->{$ctrlName};
        if ( not defined($ctrlHbas) ) {
            $ctrlHbas = [];
            $ctrlHbasMap->{$ctrlName} = $ctrlHbas;
        }
        push( @$ctrlHbas, $hbaInfo );
    }

    my @ctrls;
    my @ctrlInfoLines = $ssh->capture('svcinfo lsnode -nohdr');
    foreach my $line (@ctrlInfoLines) {
        chomp($line);
        my $name = ( split( /\s+/, $line ) )[1];
        my $ctrlInfo = {};
        $ctrlInfo->{NAME}           = $name;
        $ctrlInfo->{ETH_INTERFACES} = $ctrlNicsMap->{$name};
        $ctrlInfo->{HBA_INTERFACES} = $ctrlHbasMap->{$name};

        push( @ctrls, $ctrlInfo );
    }
    $data->{CONTROLLERS} = \@ctrls;

    $ssh->disconnect();
    return $data;
}

1;

