#!/usr/bin/perl

package StorageEmcVnx;
use strict;
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");
use CollectUtils;

sub new {
    my ( $type, %args ) = @_;
    my $self        = {};
    my $stonavmHome = $args{STONAVM_HOME};
    if ( not defined($stonavmHome) or $stonavmHome == '' ) {
        $stonavmHome = abs_path("$FindBin::Bin/../../../tools/stonavm");
    }

    my $node = $args{node};
    $self->{node} = $node;

    my $host     = $node->{host};
    my $user     = $node->{user};
    my $password = $node->{password};

    $self->{host}        = $host;
    $self->{user}        = $user;
    $self->{password}    = $password;
    $self->{stonavmHome} = $stonavmHome;

    $ENV{'LIBPATH'}         = "$stonavmHome:$ENV{LIBPATH}";
    $ENV{'SHLIB_PATH'}      = "$stonavmHome/lib:$ENV{SHLIB_PATH}";
    $ENV{'LD_LIBRARY_PATH'} = "$stonavmHome/lib:$ENV{LD_LIBRARY_PATH}";
    $ENV{'STONAVM_HOME'}    = "$stonavmHome";
    $ENV{'STONAVM_ACT'}     = 'on';

    #取消每次“y" or "no"提示
    $ENV{'STONAVM_RSP_PASS'} = 'on';
    $ENV{'PATH'}             = "$ENV{PATH}:$stonavmHome";

    my $utils = CollectUtils->new();
    $self->{collectUtils} = $utils;
    bless( $self, $type );
    return $self;
}

sub getCmdOut {
    my ( $self, %args ) = @_;
    my $utils       = $self->{collectUtils};
    my $stonavmHome = $self->{stonavmHome};
    my $command     = $args{cmd};
    my $cmd         = "$stonavmHome/$command";
    return $utils->getCmdOut($cmd);
}

sub getCmdOutLines {
    my ( $self, %args ) = @_;
    my $utils       = $self->{collectUtils};
    my $stonavmHome = $self->{stonavmHome};
    my $command     = $args{cmd};
    my $cmd         = "$stonavmHome/$command";
    return $utils->getCmdOutLines($cmd);
}

sub collect {
    my ($self) = @_;
    my $data = {};
    $data->{VENDOR} = 'Hitachi';
    $data->{BRAND}  = 'AMS';
    $data->{UPTIME} = undef;

    #   % auunitref
    #   Name Group
    #    Type Construction Connection Type Error Monitoring Communication Type IP Ad
    #   dress/Host Name/Device Name
    #   sms100
    #    SMS100 Dual TCP/IP(LAN) Enable Non-secure 192.168.3.100
    #    192.168.3.101
    #    ams500
    #    AMS500 Dual TCP/IP(LAN) Enable Non-secure 192.168.3.102
    #    192.168.3.103
    #    AMS2300_85000045_IPv6
    #    AMS2300 Single TCP/IP(LAN) Enable Non-secure fe80:
    #    :020a:e4ff:ff67:6ee8
    my $host = $self->{host};
    my $unitName;
    my $registeredLines = $self->getCmdOutLines('auunitref');
    foreach my $registered (@$registeredLines) {
        if ( $registered =~ /$host/ ) {
            my @registered_info = split( /\s+/, $registered );
            $unitName = @registered_info[0];
        }
    }

    if ( not defined($unitName) or $unitName eq '' ) {

        #TODO 自动注册？
        exit(0);
    }

    #% auunitinfo -unit ams500a1
    #Array Unit Type : AMS500
    #Construction : Dual
    #Serial Number : 75010026
    #Firmware Revision : 0771/A-M
    #CTL IP Address Subnet Mask Default Gateway
    # 0 192.168.0.1 255.255.255.0 192.168.0.100
    # 1 192.168.0.2 255.255.255.0 192.168.0.100
    #%
    my $infoOut = $self->getCmdOut("auunitinfo -unit $unitName");
    if ( $infoOut =~ /Array\s+Unit\s+Type\s+:\s+(\S+)/ ) {
        $data->{MODEL} = $1;
    }
    if ( $infoOut =~ /Serial\s+Number\s+:\s+(\S+)/ ) {
        $data->{SN} = $1;
    }

    #% auluref -unit ams2300a1 –g
    #Stripe RAID DP RAID Number
    # LU Capacity Size  Group Pool Level Type of Paths Status
    # 0  100.0MB  256KB 0 N/A 6( 9D+2P) SAS 1 Normal
    # 1  100.0MB  256KB 0 N/A 6( 9D+2P) SAS 0 Normal
    #%
    my $lunOutInfo      = $self->getCmdOutLines("auluref -unit $unitName -g");
    my @lunOutInfoLines = splice( @$lunOutInfo, 0, 2 );
    my $lunsMap         = {};
    my @luns            = ();
    foreach my $line (@lunOutInfoLines) {
        chomp($line);
        my @lineInfo = split( /\s+/, $line );
        my ( $name, $capacity, $size, $type, $poolname );

        $name     = $lineInfo[0];
        $capacity = int( $lineInfo[1] * 100 + 0.5 ) / 100;
        $size     = $lineInfo[2];
        $type     = $lineInfo[6];
        $poolname = $lineInfo[5];

        my $lun = {};
        $lun->{NAME}     = $name;
        $lun->{CAPACITY} = $capacity;
        $lun->{TYPE}     = $type;

        push( @luns, $lun );

        my $lunsInPool = $lunsMap->{$poolname};
        if ( not defined($lunsInPool) ) {
            $lunsInPool = [];
            $lunsMap->{$poolname} = $lunsInPool;
        }
        push( @$lunsInPool, $lun );
    }

    #$data->{LUNS} = \@luns;

    #% audppool -unit HUS110 -refer -t
    # DP RAID Stripe
    # Pool Level     Total   Capacity Consumed Capacity Type Status Reconstruction Progress Size
    # 0    6(6D+2P)  1.0TB    0.0TB      SAS                 Normal    N/A            64KB
    #%
    my $poolOutInfo      = $self->getCmdOutLines("audppool -unit $unitName -refer");
    my @poolOutInfoLines = splice( @$poolOutInfo, 0, 2 );
    my @pools            = ();
    foreach my $line (@poolOutInfoLines) {
        chomp($line);
        my @lineInfo = split( /\s+/, $line );
        my ( $pool, $level, $total, $capacity );

        $pool     = $lineInfo[0];
        $level    = $lineInfo[1];
        $total    = int( $lineInfo[2] * 1024 * 100 + 0.5 ) / 100;
        $capacity = $lineInfo[3];

        my $pool = {};
        $pool->{NAME}     = $pool;
        $pool->{LEVEL}    = $level;
        $pool->{CAPACITY} = $total;
        $pool->{LUNS}     = $lunsMap->{$pool};

        push( @pools, $pool );
    }

    $data->{POOLS} = \@pools;
    return $data;
}

1;

