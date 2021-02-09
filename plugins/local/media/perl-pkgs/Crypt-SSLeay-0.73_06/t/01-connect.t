use strict;
use Test::More tests => 8;
use if ($^O ne 'MSWin32'), 'POSIX';
eval "setlocale(LC_MESSAGES, 'C');" if $^O ne 'MSWin32';

use Net::SSL;

# ensure no proxification takes place
$ENV{NO_PROXY} = '127.0.0.1';

my $sock;
eval {
    $sock = Net::SSL->new(
        PeerAddr => '127.0.0.1',
        PeerPort => 443,
        Timeout  => 3,
    );
};

my $test_name = 'Net::SSL->new';
if ($@) {
    my $fail = $@;
    if ($fail =~ /\AConnect failed:/i) {
        pass( "$test_name - expected failure" );
    }
    elsif ($fail =~ /\ASSL negotiation failed:/i) {
        pass( "$test_name - expected failure (443 in use)" );
    }
    else {
        fail( "$test_name" );
        diag( $fail );
    }
}
else {
    ok( defined $sock, $test_name );
}

SKIP: {
    skip( "nothing listening on localhost:443", 7 )
        unless defined $sock;

    is( ref($sock), 'Net::SSL', 'blessed socket' );

    eval { $sock->accept };
    like ($@, qr(\Aaccept not implemented for Net::SSL sockets),
        'accept() not implemented'
    );

    eval { $sock->getc };
    like ($@, qr(\Agetc not implemented for Net::SSL sockets),
        'getc() not implemented'
    );

    eval { $sock->ungetc };
    like ($@, qr(\Aungetc not implemented for Net::SSL sockets),
        'ungetc() not implemented'
    );

    eval { $sock->getlines };
    like ($@, qr(\Agetlines not implemented for Net::SSL sockets),
        'getlines() not implemented'
    );

    # RT #90803: Don't whether $sock->blocking returns 1 or 0.
    # Instead, test true/false.
    ok( $sock->blocking, 'socket is blocking' );
    $sock->blocking(0);
    ok( !$sock->blocking, 'socket is now non-blocking' );
}
