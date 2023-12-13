#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../plib/lib/perl5";

use strict;

package FireWallHillStone;

use FireWallBase;
our @ISA = qw(FireWallBase);

use NetExpect;

sub before {
    my ($self) = @_;

    #SN可能要调整，如果有多个可能，就在数组里添加
    $self->addScalarOid(
        SN       => ['1.3.6.1.4.1.28557.2.2.1.1.0'],
        IOS_INFO => '1.3.6.1.4.1.28557.2.2.1.2.0'
    );
}

sub after {
    my ($self) = @_;

    my $data = $self->{DATA};

    my $nodeInfo = $self->{node};

    if ( not defined( $data->{DEV_NAME} ) and defined( $nodeInfo->{username} ) and lc( $nodeInfo->{username} ) ne 'snmp' ) {
        print("INFO: Can not find DEV_NAME by snmp, try ssh.\n");
        my $ssh = NetExpect->new(
            host     => $nodeInfo->{host},
            port     => $nodeInfo->{protocolPort},
            protocol => 'ssh',
            username => $nodeInfo->{username},
            password => $nodeInfo->{password},
            timeout  => $self->{timeout}
        );

        $ssh->login();

        $ssh->runCmd('terminal length 0');    #不分页

        my $verLine = $ssh->runCmd('show version');
        print("INFO: $verLine\n");
        if ( $verLine =~ /Product\s+name:\s*(\S+)\s*S\/N:\s*(\S+)/i ) {
            $data->{DEV_NAME} = $1;
            $data->{SN}       = $2;
        }
    }

    return $data;
}

1;

