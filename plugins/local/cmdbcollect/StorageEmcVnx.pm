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
    my $self    = {};
    my $binPath = $args{binPath};
    if ( not defined($binPath) or $binPath == '' ) {
        $binPath = abs_path("$FindBin::Bin/../../../tools/Navisphere/bin/naviseccli");
    }
    my $host     = $args{host};
    my $user     = $args{user};
    my $password = $args{password};

    $self->{host}     = $host;
    $self->{user}     = $user;
    $self->{password} = $password;
    $self->{binPath}  = $binPath;

    my $naviseccli = "$binPath -h $host -Scope 0 -User $user -Password $password";
    $self->{naviseccli} = $naviseccli;

    my $utils = CollectUtils->new();
    $self->{collectUtils} = $utils;
    bless( $self, $type );
    return $self;
}

sub getCmdOut {
    my ( $self, %args ) = @_;
    my $utils      = $self->{collectUtils};
    my $naviseccli = $self->{naviseccli};
    my $command    = $args{cmd};
    my $cmd        = "$naviseccli $command";
    return $utils->getCmdOut( $cmd );
}

sub getCmdOutLines {
    my ( $self, %args ) = @_;
    my $utils      = $self->{collectUtils};
    my $naviseccli = $self->{naviseccli};
    my $command    = $args{cmd};
    my $cmd        = "$naviseccli $command";
    return $utils->getCmdOutLines( $cmd );
}

sub collect {
    my ($self) = @_;
    my $data   = {};
    my $out    = $self->getCmdOut('getagent');
    if ( $out =~ /Model:\s+(\S+)\s+/ ) {
        $data->{MODEL} = $1;
    }
    if ( $out =~ /Serial\s+No:\s+(\S+)\s+/ ) {
        $data->{SERIAL_NO} = $1;
    }
    if ( $out =~ /Name:\s+(\S+)\s+/ ) {
        $data->{HOSTNAME} = $1;
    }

    my $lun_out = $self->getCmdOut('getlun');
    my @arr_lun = $lun_out =~ /LOGICAL UNIT NUMBER(.*?)MirrorView/sg;
    my @luns    = ();
    foreach my $line (@arr_lun) {
        $line =~ s/^\s+|\s+$//g;

        my ( $name, $uuid, $size, $id );
        if ( $line =~ /^(\d+)\s+/ ) {
            $id = $1;
        }
        if ( $line =~ /Name\s*(.+)\n/ ) {
            $name = $1;
            $name =~ s/^\s+|\s+$//g;
        }
        if ( $line =~ /UID:\s*(\S+)\s*/ ) {
            $uuid = $1;
        }
        if ( $line =~ /LUN\s*Capacity\(Megabytes\):\s*(\d+)\s*/ ) {
            $size = $1;
            $size = int( $size / 1024 );
        }

        my $lun = {};
        $lun->{ID}   = $id;
        $lun->{NAME} = $name;
        $lun->{UUID} = $uuid;
        $lun->{SIZE} = $size;
        push( @luns, $lun );
    }
    $data->{LUNS} = \@luns;

    my $pool_out = $self->getCmdOut('getrg');
    my @arr_pool = $pool_out =~ /RaidGroup ID:(.*?)Legal RAID types:/sg;
    my @pools    = ();
    foreach my $line (@arr_pool) {
        $line =~ s/^\s+|\s+$//g;

        my ( $name, $size, $free );
        if ( $line =~ /^(\d+)\s+/ ) {
            $name = $1;
        }
        if ( $line =~ /Logical Capacity \(Blocks\):\s+(\S+)\s+/ ) {
            $size = $1;
            $size = int( $size / 2048 / 1024 );
            $size = $size . 'GB';
        }
        if ( $line =~ /Free Capacity \(Blocks,non-contiguous\):\s+(\d+)\s+/ ) {
            $free = $1;
            $free = int( $free / 2048 / 1024 );
            $free = $free . 'GB';
        }

        my @pool_lun = ();
        if ( $line =~ /List of luns:\s*(.*)\s*/ ) {
            my $pool_lunid = $1;
            $pool_lunid =~ s/^\s+|\s+$//g;
            foreach my $pool (@luns) {
                my $rid = $pool->{ID};
                if ( $rid eq $pool_lunid ) {
                    push( @pool_lun, { 'VALUE' => $rid } );
                }
            }
        }

        my $pool = {};
        $pool->{NAME}        = $name;
        $pool->{SIZE}        = $size;
        $pool->{FREE}        = $size;
        $pool->{CONTAIN_LUN} = \@pool_lun;

        push( @pools, $pool );
    }

    $data->{POOLS} = \@pools;

    return $data;
}

1;

