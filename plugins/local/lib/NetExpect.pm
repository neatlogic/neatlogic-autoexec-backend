#!/usr/bin/env perl

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

    if(not defined($attr{verbose})){
        $self->{verbose} = 0;
    }

    bless( $self, $type );

    return $self;
}

sub checkIfMatched {
    my ( $self, $spawn, $matchedIdx, $msg ) = @_;
    if ( not defined($matchedIdx) ) {
        $spawn->hard_close();
        die("ERROR: $msg\n");
    }
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
    $spawn->timeout($timeout);

    my $cmd;
    if ( $protocol eq 'ssh' ) {
        $cmd = qq(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p$port $username\@$host);
    }
    else {
        $cmd = qq(telnet $host $port);
    }
    $spawn->spawn($cmd);
    $spawn->slave->stty(qw(raw -echo));

    my $matchedIdx;
    $matchedIdx = $spawn->expect(
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
    $self->checkIfMatched($spawn, $matchedIdx, "Expect the terminal shell request username and password failed.");

    $matchedIdx = $spawn->expect(
        [
            qr/$prompt/ => sub {
                if($verbose == 1){
                    print("INFO: Login $username\@$host:$port success.\n");
                }
            }
        ],
        [
            qr/password:/i => sub {
                my $msg = $spawn->before();
                $spawn->hard_close();
                die("ERROR: Login $username\@$host:$port failed, invalid username or password.\n");
            }
        ],
        [
            qr/(ssh: connect to host .*)$/ => sub {
                my $msg = $spawn->match();
                $spawn->hard_close();
                die( "ERROR: Login failed. " . $msg . "\n" );
            }
        ],
        [
            qr/connection refused/i => sub {
                my $msg = $spawn->match();
                $spawn->hard_close();
                die( "ERROR: Login failed. " . $msg . "\n" );
            }
        ],
        [
            qr/\nPermission denied, please try again\.\s*/i => sub {
                my $msg = $spawn->match();
                $spawn->hard_close();
                die( "ERROR: Login failed. " . $msg . "\n" );
            }
        ],
        [
            qr/authentication failed/i => sub {
                my $msg = $spawn->match();
                $spawn->hard_close();
                die( "ERROR: Login failed. " . $msg . "\n" );
            }
        ]
    );

    $self->checkIfMatched($spawn, $matchedIdx, "Login $username\@$host:$port timeout, expect command prompt timeout.");

    $self->{spawn} = $spawn;
    return $spawn;
}

sub backup {
    my ( $self, $fullPageCmd, $configCmd, $exitCmd ) = @_;

    my $spawn   = $self->{spawn};
    my $prompt  = $self->{prompt};

    my $cmdOut = '';
    $spawn->log_file(
        sub {
            my $content = shift;
            $cmdOut = $cmdOut . $content;
        }
    );

    my $matched;
    $spawn->send("$fullPageCmd\n");
    $matched = $spawn->expect( '-re', qr/$prompt/ );
    $self->checkIfMatched($spawn, $matched, "Execute command:$fullPageCmd failed.");

    $spawn->send("$configCmd\n");
    $matched = $spawn->expect( '-re', qr/$prompt/ );
    $self->checkIfMatched($spawn, $matched, "Execute command:$configCmd failed.");

    $spawn->send("$exitCmd\n");
    $matched = $spawn->expect('-re', eof => sub { } );

    $cmdOut = substr( $cmdOut, rindex( $cmdOut, $configCmd ) + length($configCmd) + 1 );
    $cmdOut = substr( $cmdOut, 0, rindex( $cmdOut, $exitCmd ) );
    $cmdOut = substr( $cmdOut, 0, rindex( $cmdOut, "\n" ) + 1 );

    return $cmdOut;
}

sub runCmd {
    my ( $self, $cmd ) = @_;

    my $spawn   = $self->{spawn};
    my $prompt  = $self->{prompt};

    $spawn->send("$cmd\n");
    my $matched = $spawn->expect('-re', qr/$prompt/ );
    $self->checkIfMatched($spawn, $matched, "Execute command:$cmd failed.");
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
