#!/usr/bin/perl

package NetExpect;
use strict;
use Expect;

sub new {
    my ( $type, %attr ) = @_;

    $| = 1;

    my $self = {};
    $self->{prompt} = '[\]\$\>\#]\s*$';
    if ( defined( $attr{prompt} ) and $attr{prompt} ne '' ) {
        $self->{prompt} = $attr{prompt};
    }

    $self->{host}     = $attr{host};
    $self->{port}     = $attr{port};
    $self->{username} = $attr{username};
    $self->{password} = $attr{password};
    $self->{protocol} = $attr{protocol};
    $self->{timeout}  = $attr{timeout};
    $self->{verbose}  = $attr{verbose};

    bless( $self, $type );

    return $self;
}

sub login {
    my ($self) = @_;

    my $prompt   = $self->{prompt};
    my $host     = $self->{host};
    my $port     = $self->{port};
    my $username = $self->{username};
    my $password = $self->{password};
    my $protocol = $self->{protocol};
    my $verbose  = $self->{verbose};
    my $timeout  = $self->{timeout};

    my $spawn = Expect->new();
    if ( $verbose == 1 ) {
        $spawn->log_stdout(1);
    }
    else {
        $spawn->log_stdout(0);
    }

    $spawn->raw_pty(1);
    $spawn->restart_timeout_upon_receive(1);
    $spawn->max_accum(512);

    my $cmd;
    if ( $protocol eq 'ssh' ) {
        $cmd = qq(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p$port $username\@$host);
    }
    else {
        $cmd = qq(telnet $host $port);
    }
    $spawn->spawn($cmd);
    $spawn->slave->stty(qw(raw -echo));

    $spawn->expect(
        $timeout,
        [
            qr/username:/i => sub {
                $spawn->send("$username\n");
                $spawn->exp_continue;
            }
        ],
        [
            qr/password:/i => sub {
                $spawn->send("$password\n");
            }
        ],
        [
            qr/\(yes\/no\)\?\s*$/ => sub {
                $spawn->send("yes\n");
                $spawn->exp_continue;
            }
        ]
    );

    $spawn->expect(
        $timeout,
        [
            qr/$prompt/ => sub {
                print("INFO: Login $username\@$host:$port success.\n");
            }
        ],
        [
            qr/password:/i => sub {
                print( $spawn->before() );
                print("ERROR: Login $username\@$host:$port failed.\n");
                $spawn->hard_close();
                exit(2);
            }
        ],
        [
            qr/(ssh: connect to host .*)$/ => sub {
                print( "ERROR: Login failed. " . $spawn->match() . "\n" );
                $spawn->hard_close();
                exit(2);
            }
        ],
        [
            qr/connection refused/i => sub {
                print( "ERROR: Login failed. " . $spawn->match() . "\n" );
                $spawn->hard_close();
                exit(2);
            }
        ],
        [
            qr/\nPermission denied, please try again\.\s*/i => sub {
                print( "ERROR: Login failed. " . $spawn->match() . "\n" );
                $spawn->hard_close();
                exit(2);
            }
        ],
        [
            qr/authentication failed/i => sub {
                print( "ERROR: Login failed. " . $spawn->match() . "\n" );
                $spawn->hard_close();
                exit(2);
            }
        ],
        [
            timeout => sub {
                print("ERROR: Login $username\@$host:$port failed.\n");
                $spawn->hard_close();
                exit(3);
            }
        ]
    );

    $self->{spawn} = $spawn;
    return $spawn;
}

sub backup {
    my ( $self, $fullPageCmd, $configCmd, $exitCmd ) = @_;

    my $spawn   = $self->{spawn};
    my $timeout = $self->{timeout};
    my $prompt  = $self->{prompt};

    my $cmdOut = '';
    $spawn->log_file(
        sub {
            my $content = shift;
            $cmdOut = $cmdOut . $content;
        }
    );

    $spawn->send("$fullPageCmd\n");
    $spawn->expect( $timeout, '-re', qr/$prompt/ );

    $spawn->send("$configCmd\n");
    $spawn->expect( $timeout, '-re', qr/$prompt/ );

    $spawn->send("$exitCmd\n");
    $spawn->expect( $timeout, '-re', eof => sub { } );

    $cmdOut = substr( $cmdOut, rindex( $cmdOut, $configCmd ) + length($configCmd) + 1 );
    $cmdOut = substr( $cmdOut, 0, rindex( $cmdOut, $exitCmd ) );
    $cmdOut = substr( $cmdOut, 0, rindex( $cmdOut, "\n" ) + 1 );
    return $cmdOut;
}

sub runCmd {
    my ( $self, $cmd ) = @_;

    my $spawn   = $self->{spawn};
    my $timeout = $self->{timeout};
    my $prompt  = $self->{prompt};

    $spawn->send("$cmd\n");
    $spawn->expect( $timeout, '-re', qr/$prompt/ );

}

sub close {
    my ( $self, $exitCmd ) = @_;
    my $spawn = $self->{spawn};

    if ( defined($spawn) ) {
        $self->runCmd($exitCmd);
        $spawn->soft_close();
        $spawn->hard_close();
    }
}

1;
