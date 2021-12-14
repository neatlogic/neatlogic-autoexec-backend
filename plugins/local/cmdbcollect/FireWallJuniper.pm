#!/usr/bin/perl
use strict;
use FindBin;
use Cwd qw(abs_path);
use lib abs_path("$FindBin::Bin/lib");
use lib abs_path("$FindBin::Bin/../lib");
use lib abs_path("$FindBin::Bin/../lib/perl-lib/lib/perl5");

package FireWallJuniper;

use FireWallBase;
our @ISA = qw(FireWallBase);

use SSHExpect;

sub before {
    my ($self) = @_;

    #SN可能要调整，如果有多个可能，就在数组里添加
    #$self->addScalarOid( SN => [ '1.3.6.1.4.1.9.3.6.3.0', '1.3.6.1.4.1.9.5.1.2.19.0', '1.3.6.1.2.1.47.1.1.1.1.11.1001', '1.3.6.1.2.1.47.1.1.1.1.11.2001', '1.3.6.1.4.1.9.9.92.1.1.1.2.0' ] );
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

        my $verLine = $ssh->runCmd( 'show version', 0 );
        print("INFO: $verLine\n");
        if ( $verLine =~ /Product\s+name:\s*(\S+)\s*S\/N:\s*(\S+)/i ) {
            $data->{DEV_NAME} = $1;
            $data->{SN}       = $2;
        }
    }

    return $data;
}

1;
