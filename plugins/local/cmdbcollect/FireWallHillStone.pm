#!/usr/bin/perl
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");

package FireWallHillStone;
use strict;

use JSON;
use CollectUtils;
use SSHExpect;

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
    $data->{VENDOR} = 'HillStone';
    $data->{BRAND}  = 'HillStone';
    
    my $nodeInfo = $self->{node};

    my $ssh = SSHExpect->new(
        host     => $nodeInfo->{host},
        port     => $nodeInfo->{protocolPort},
        username => $nodeInfo->{username},
        password => $nodeInfo->{password},
        timeout  => $self->{timeout}
    );

    $ssh->login();
    $ssh->configTerminal();

    my $verLine = $ssh->runCmd( 'show version', 4 );
    print("INFO: $verLine\n");
    if ( $verLine =~ /Product\s+name:\s*(\S+)\s*S\/N:\s*(\S+)/i ) {
        $data->{DEV_NAME} = $1;
        $data->{SN}       = $2;
    }

    return $data;
}

1;

