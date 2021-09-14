#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");

package StorageEMC_Vnx;
use strict;
use JSON;
use CollectUtils;

sub new {
    my ( $type, %args ) = @_;
    my $self    = {};
    my $binPath = $args{binPath};
    if ( not defined($binPath) or $binPath == '' ) {
        $binPath = abs_path("$FindBin::Bin/../../../tools/storage/Navisphere/bin/naviseccli");
    }
    my $node = $args{node};
    $self->{node} = $node;

    my $host     = $node->{host};
    my $user     = $node->{username};
    my $password = $node->{password};

    my $naviSecCLI = "$binPath -h $host -Scope 0 -User $user -Password $password";
    $self->{naviSecCLI} = $naviSecCLI;

    my $utils = CollectUtils->new();
    $self->{collectUtils} = $utils;

    bless( $self, $type );
    return $self;
}

sub getCmdOut {
    my ( $self, %args ) = @_;
    my $utils      = $self->{collectUtils};
    my $naviSecCLI = $self->{naviSecCLI};
    my $command    = $args{cmd};
    my $cmd        = "$naviSecCLI $command";
    return $utils->getCmdOut($cmd);
}

sub getCmdOutLines {
    my ( $self, %args ) = @_;
    my $utils      = $self->{collectUtils};
    my $naviSecCLI = $self->{naviSecCLI};
    my $command    = $args{cmd};
    my $cmd        = "$naviSecCLI $command";
    return $utils->getCmdOutLines($cmd);
}

sub collect {
    my ($self) = @_;
    my $data   = {};
    my $out    = $self->getCmdOut('getagent');

    $data->{VENDOR} = 'Dell';
    $data->{BRAND}  = 'EMC';
    $data->{UPTIME} = undef;

    if ( $out =~ /Model:\s+(\S+)\s+/ ) {
        $data->{MODEL} = $1;
    }
    if ( $out =~ /Serial\s+No:\s+(\S+)\s+/ ) {
        $data->{SN} = $1;
    }
    if ( $out =~ /Name:\s+(\S+)\s+/ ) {
        $data->{DEV_NAME} = $1;
    }

    my $lunOutInfo   = $self->getCmdOut('getlun');
    my @lunInfoLines = $lunOutInfo =~ /LOGICAL UNIT NUMBER(.*?)MirrorView/sg;

    my $lunsMap = {};
    my @luns    = ();
    foreach my $line (@lunInfoLines) {
        $line =~ s/^\s+|\s+$//g;

        my ( $name, $uuid, $size, $id );
        if ( $line =~ /^(\d+)\s+/ ) {
            $id = $1;
        }
        elsif ( $line =~ /Name\s*(.+?)\s*\n/ ) {
            $name = $1;
        }
        elsif ( $line =~ /UID:\s*(\S+)\s*/ ) {
            $uuid = $1;
        }
        elsif ( $line =~ /LUN\s*Capacity\(Megabytes\):\s*(\d+)\s*/ ) {
            $size = $1;
            $size = int( $size * 100 / 1024 + 0.5 ) / 100;
        }

        my $lun = {};
        $lun->{ID}    = $id;
        $lun->{NAME}  = $name;
        $lun->{LUNID} = $uuid;
        $lun->{SIZE}  = $size;
        push( @luns, $lun );
        $lunsMap->{$id} = $lun;
    }
    $data->{LUNS} = \@luns;

    my $poolOutInfo   = $self->getCmdOut('getrg');
    my @poolInfoLines = $poolOutInfo =~ /RaidGroup ID:(.*?)Legal RAID types:/sg;

    my @pools = ();
    foreach my $line (@poolInfoLines) {
        $line =~ s/^\s+|\s+$//g;

        my ( $name, $size, $free );
        if ( $line =~ /^(\d+)\s+/ ) {
            $name = $1;
        }
        elsif ( $line =~ /Logical Capacity \(Blocks\):\s+(\S+)\s+/ ) {
            $size = $1;
            $size = int( $size * 100 / 2048 / 1024 + 0.5 ) / 100;
            $size = $size;
        }
        elsif ( $line =~ /Free Capacity \(Blocks,non-contiguous\):\s+(\d+)\s+/ ) {
            $free = $1;
            $free = int( $free * 100 / 2048 / 1024 + 0.5 ) / 100;
            $free = $free;
        }

        my @lunsInPool = ();
        if ( $line =~ /List of luns:\s*(.*?)\s*/ ) {
            my $lunId = $1;
            if ( defined( $lunsMap->{$lunId} ) ) {
                push( @lunsInPool, $lunsMap->{$lunId} );
            }
        }

        my $pool = {};
        $pool->{NAME} = $name;
        $pool->{SIZE} = $size;
        $pool->{FREE} = $size;
        $pool->{LUNS} = \@lunsInPool;

        push( @pools, $pool );
    }

    $data->{STORAGE_POOLS} = \@pools;

    return $data;
}

1;

