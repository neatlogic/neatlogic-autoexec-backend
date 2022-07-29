#!/usr/bin/perl

package SSHExpect;
use strict;
use Expect;

sub new {
    my ( $type, %attr ) = @_;

    $| = 1;

    my $self   = {};
    my $prompt = '[\]\$\>\#]\s*$';
    $self->{prompt}    = $attr{prompt};
    $self->{host}      = $attr{host};
    $self->{port}      = $attr{port};
    $self->{username}  = $attr{username};
    $self->{password}  = $attr{password};
    $self->{timeout}   = $attr{timeout};
    $self->{startLine} = $attr{startLine};
    $self->{verbose}   = $attr{verbose};
    $self->{exitCmd}   = $attr{exitCmd};
    $self->{clsCmd}    = $attr{clsCmd};
    $self->{cfgCmd}    = $attr{cfgCmd};
    $self->{cmds}      = $attr{cmds};

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

    my $sshCmd = qq(ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -p$port $username\@$host);

    my $cmdOut = '';

    $spawn->spawn($sshCmd);
    $spawn->slave->stty(qw(raw -echo));

    $spawn->expect(
        $timeout,
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
                print("INFO: login $username\@$host:$port success.\n");
            }
        ],
        [
            qr/password:/i => sub {
                print( $spawn->before() );
                print("ERROR: login $username\@$host:$port failed.\n");
                $spawn->hard_close();
                exit(2);
            }
        ],
        [
            qr/(ssh: connect to host .*)$/ => sub {
                print( "ERROR: login failed. " . $spawn->match() . "\n" );
                $spawn->hard_close();
                exit(2);
            }
        ],
        [
            qr/\nPermission denied, please try again\.\s*/i => sub {
                print( "ERROR: login failed. " . $spawn->match() . "\n" );
                $spawn->hard_close();
                exit(2);
            }
        ],
        [
            timeout => sub {
                print("ERROR: login $username\@$host:$port failed.\n");
                $spawn->hard_close();
                exit(3);
            }
        ]
    );

    $self->{spawn} = $spawn;
    return $spawn;
}

sub configTerminal {
    my ($self)  = @_;
    my $spawn   = $self->{spawn};
    my $prompt  = $self->{prompt};
    my $timeout = $self->{timeout};
    my $clsCmd  = $self->{clsCmd};

    if ( not defined($spawn) ) {
        $self->login();
    }

    $spawn->send("$clsCmd\n");
    $spawn->expect( $timeout, '-re', qr/$prompt/ );
}

sub runCmd {
    my ( $self, $cmd ) = @_;

    my $timeout   = $self->{timeout};
    my $spawn     = $self->{spawn};
    my $timeout   = $self->{timeout};
    my $startLine = $self->{startLine};

    if ( not defined($cmd) or $cmd eq '' ) {
        $cmd = $self->{cfgCmd};
    }

    if ( not defined($spawn) ) {
        $self->login();
    }

    my $cmdOut = '';
    $spawn->log_file(
        sub {
            my $content = shift;
            $cmdOut = $cmdOut . $content;
        }
    );

    $spawn->send("$cmd\n");

    #等待结束
    $spawn->expect( $timeout, '-re', eof => sub { } );

    #$spawn->log_file(undef);

    #去掉最后一行的命令提示行
    $cmdOut = substr( $cmdOut, 0, rindex( $cmdOut, "\n" ) + 1 );

    #去掉命令输出的头几行
    for ( my $i = 0 ; $i < $startLine ; $i++ ) {
        $cmdOut = substr( $cmdOut, index( $cmdOut, "\n" ) + 1 );
    }

    return $cmdOut;
}

sub runCmds {
    my ($self) = @_;

    my $cmds = $self->{cmds};

    my $cmdsOut = '';
    foreach my $cmd (@$cmds) {
        $cmdsOut = $cmdsOut . $self->runCmd($cmd);
    }

    return $cmdsOut;
}

sub close {
    my ($self) = @_;
    my $spawn = $self->{spawn};

    if ( defined($spawn) ) {
        $spawn->send( $self->{exitCmd} . "\n" );
        $spawn->soft_close();
    }
    exit(0);
}

1;
