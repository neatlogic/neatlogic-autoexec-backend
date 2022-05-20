#!/usr/bin/perl
use strict;
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../pllib/lib/perl5");

package FireWallHillStone;

use FireWallBase;
our @ISA = qw(FireWallBase);

use SSHExpect;

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
    }

    return $data;
}

1;

