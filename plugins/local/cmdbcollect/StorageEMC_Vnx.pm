#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../plib/lib/perl5";

use strict;

package StorageEMC_Vnx;
use Cwd qw(abs_path);
use JSON;
use CollectUtils;

sub new {
    my ( $type, %args ) = @_;
    my $self = {};

    my $cliHome = $args{cliHome};
    if ( not defined($cliHome) or $cliHome == '' ) {
        $cliHome = abs_path("$FindBin::Bin/../../../tools/storage/Navisphere");
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

    my $host     = $node->{host};
    my $user     = $node->{username};
    my $password = $node->{password};

    my $naviSecCLI = "naviseccli -h $host -Scope 0 -User $user -Password $password";
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

        my ( $name, $wwn, $size, $id );
        if ( $line =~ /^(\d+)\s+/ ) {
            $id = $1;
        }
        elsif ( $line =~ /Name\s*(.+?)\s*\n/ ) {
            $name = $1;
        }
        elsif ( $line =~ /UID:\s*(\S+)\s*/ ) {
            $wwn = $1;
        }
        elsif ( $line =~ /LUN\s*Capacity\(Megabytes\):\s*(\d+)\s*/ ) {
            $size = $1;
            $size = int( $size * 100 / 1024 + 0.5 ) / 100;
        }

        my $lun = {};
        $lun->{ID}       = $id;
        $lun->{NAME}     = $name;
        $lun->{WWN}      = $wwn;
        $lun->{CAPACITY} = $size;
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

                #push( @lunsInPool, $lunsMap->{$lunId} );
                my $lunInfo = $lunsMap->{$lunId};
                if ( defined($lunInfo) ) {
                    $lunInfo->{POOL_NAME} = $name;
                }
            }
        }

        my $pool = {};
        $pool->{NAME}      = $name;
        $pool->{CAPACITY}  = $size;
        $pool->{USED}      = $size - $free;
        $pool->{AVAILABLE} = $free;
        $pool->{USED_PCT}  = int( ( $size - $free ) * 10000 / $size * 0.5 ) / 100;

        #$pool->{LUNS}         = \@lunsInPool;

        push( @pools, $pool );
    }

    $data->{POOLS} = \@pools;

    return $data;
}

1;

