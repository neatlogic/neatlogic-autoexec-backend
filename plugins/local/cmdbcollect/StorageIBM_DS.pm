#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");

package StorageIBM_DS;
use strict;

use JSON;
use CollectUtils;

sub new {
    my ( $type, %args ) = @_;
    my $self = {};

    my $binPath = $args{binPath};
    if ( not defined($binPath) or $binPath == '' ) {
        $binPath = abs_path("$FindBin::Bin/../../../tools/storage/dscli");
    }
    my $path = $ENV{PATH};
    if ( $path !~ /\Q$binPath\E/ ) {
        $ENV{PATH} = "$binPath:$path";
    }

    my $node = $args{node};
    $self->{node} = $node;
    my $host = $node->{host};
    my $user = $node->{username};
    my $pass = $node->{password};

    my $cliCmd = "dscli -hmc1 $host  -user '$user' -passwd '$pass'";
    $self->{cliCmd} = $cliCmd;

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
    my $utils    = $self->{collectUtils};
    my $cliCmd   = $self->{cliCmd};

    my $snInfLines = $utils->getCmdOutLines("$cliCmd lssi");
    my $SN;
    my $devName;
    foreach my $line (@$snInfLines) {
        if ( $line =~ /Online/ ) {
            my @splits = split( /\s+/, $line );
            $devName = $splits[1];

            my $snInfo = $splits[2];
            if ( $snInfo =~ /IBM\.\d{4}-(\S+)/ ) {
                $SN = $1;
            }
            last;
        }
    }
    $data->{SN}       = $SN;
    $data->{DEV_NAME} = $devName;

    my $totalCapacity = 0;
    my @pools         = ();
    my $poolIdOut     = $utils->getCmdOut("$cliCmd lsextpool -s");
    while ( $poolIdOut =~ /P\d+/g ) {
        my $poolName = $&;    #match content
        my $poolInfo = {};
        $poolInfo->{NAME} = $poolName;

        my $poolInfoOut = $utils->getCmdOut("$cliCmd showextpool $poolName");
        if ( $poolInfoOut =~ /configured\s+(\S+)/ ) {
            my $poolCapacity = int( $1 * 100 + 0.5 ) / 100;
            $poolInfo->{CAPACITY} = $poolCapacity;
            $totalCapacity += $poolCapacity;
        }

        my @luns;
        my $lunInfoOut = $utils->getCmdOut("$cliCmd lsfbvol -extpool $poolName");
        foreach my $line (@$lunInfoOut) {
            if ( $line =~ /Online/ ) {
                my @splits      = split( /\s+/, $line );
                my $lunName     = $splits[0];
                my $tmpLunId    = $splits[1];
                my $lunCapacity = $splits[-3];

                my $lunId;
                my $lunIdInfo = $utils->getCmdOut("$cliCmd showfbvol $tmpLunId");
                if ( $lunIdInfo =~ /GUID\s+(\S+)/ ) {
                    $lunId = $1;
                }

                my $lunInfo = {};
                $lunInfo->{NAME}     = $lunName;
                $lunInfo->{LUN_ID}   = $lunId;
                $lunInfo->{CAPACITY} = $lunCapacity;
                push( @luns, $lunInfo );
            }
        }

        $poolInfo->{LUNS} = \@luns;

        push( @pools, $poolInfo );
    }
    $data->{CAPACITY} = $totalCapacity;
    $data->{STORAGE_POOLS}    = \@pools;

    my @hbas;
    my $hbaInfoLines = $utils->getCmdOutLines("$cliCmd lsioport");
    for ( my $i = 3 ; $i < scalar(@$hbaInfoLines) ; $i++ ) {
        my $line   = $$hbaInfoLines[$i];
        my @splits = split( /\s+/, $line );
        my $name     = $splits[0];
        my $wwn    = $splits[1];
        $wwn =~ s/..\K(?=.)/:/sg;
        my $status;
        if ( $line =~ /established/ ) {
            $status = 'UP';
        }
        else {
            $status = 'DOWN';
        }
        my $hbaInfo = {};
        $hbaInfo->{NAME}   = $name;
        $hbaInfo->{WWN}    = $wwn;
        $hbaInfo->{STATUS} = $status;
        push( @hbas, $hbaInfo );
    }

    $data->{HBA_INTERFACES} = \@hbas;
    $data->{STORAGE_POOLS}          = \@pools;

    return $data;
}

1;
