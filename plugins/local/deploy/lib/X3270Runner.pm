#!/usr/bin/perl
use strict;

use FindBin;

package X3270Runner;
use IPC::Open2;
use IO::Handle;
use IO::Select;

sub new {
    my ( $type, %args ) = @_;

    my $self = {};
    bless( $self, $type );

    $self->{toolsDir}       = $args{toolsDir};
    $self->{host}           = $args{host};
    $self->{port}           = $args{port};
    $self->{user}           = $args{user};
    $self->{pass}           = $args{pass};
    $self->{ccsid}          = $args{ccsid};
    $self->{connectTimeout} = $args{connectTimeout};

    if ( not defined( $self->{connectTimeout} ) or $self->{connectTimeout} !~ /^\d+$/ ) {
        $$self->{connectTimeout} = 5;
    }

    my $s3270Path = "$toolsDir/x3270/s3270";

    #my $s3270Path = "./s3270";
    my $pipeCmd = "$s3270Path -model 3278-2 -utf8 -charset cp$self->{ccsid} -connecttimeout $self->{connectTimeout}";

    my $childIn  = IO::Handle->new();
    my $childOut = IO::Handle->new();

    my $pid = open2( $childOut, $childIn, "$pipeCmd" );

    if ( $pid == 0 ) {
        die("ERROR: Execute $pipeCmd failed: $!\n");
    }

    $self->{pid} = $pid;
    my $sel = IO::Select->new($childOut);

    $self->{childOut} = $childOut;
    $self->{childIn}  = $childIn;
    $self->{selector} = $sel;

    $self->login();

    return $self;
}

sub doAction {
    my ( $self, $action ) = @_;

    my $childOut = $self->{childOut};
    my $childIn  = $self->{childIn};
    my $sel      = $self->{selector};

    my $screenBuf   = '';
    my @screenArray = ();
    my $status      = 'ok';

    print $childIn ("$action\n");
    my @pipeReady = $sel->can_read();

    while ( scalar(@pipeReady) > 0 ) {
        my $buf;
        $childOut->sysread( $buf, 80 * 27 );

        foreach my $line ( split( /\n/, $buf ) ) {

            #print("DEBUG:$line\n");
            if ( $line =~ /^data: (.*)$/ ) {
                $screenBuf = $screenBuf . $1 . "\n";
                push( @screenArray, $1 );
            }
            elsif ( $line =~ /^error/ ) {
                $status = 'error';
            }
            elsif ( $line =~ /^ok/ ) {
                $status = 'ok';
            }
        }

        if ( $status eq 'error' ) {
            $self->dumpScreen();
            die("ERROR: $screenBuf\n");
        }
        @pipeReady = $sel->can_read(0.25);
    }

    return ( \@screenArray, $screenBuf );
}

sub dumpScreen {
    my ($self) = @_;

    my ( $screenArray, $screen ) = $self->doAction("Ascii");

    print( '-' x 80, "\n" );
    foreach my $line (@$screenArray) {

        #print ("|$line", ' ' x (80 - length($line)) .  "|\n");
        print( $line, ' ' x ( 80 - length($line) ) . "\n" );
    }
    print( '-' x 80, "\n" );

    #my $screenHtml = '<pre>' . '-' x 82 . '</pre><br/>' . "\n";
    #foreach my $line (@$screenArray) {
    #    $screenHtml = $screenHtml . '<pre>|' . $line . ' ' x ( 80 - length($line) ) . '|</pre><br/>' . "\n";
    #}
    #$screenHtml = $screenHtml . '<pre>' . '-' x 82 . '</pre><br/>' . "\n";
    #print($screenHtml);

    return $screen;
}

sub login {
    my ($self) = @_;

    my $host = $self->{host};
    my $port = $self->{port};
    my $user = $self->{user};
    my $pass = $self->{pass};

    my $screen;

    #connect to host
    $self->doAction("Connect($host:$port)");
    $self->doAction("Wait(Output)");

    #login
    $self->doAction(qq(String("$user")));
    $self->doAction("Tab");
    $self->doAction(qq(String("$pass")));
    $self->doAction("Wait(Output)");

    my ( $screenArray, $screen ) = $self->doAction("Ascii");

    do {
        $self->doAction("Enter");
        $self->doAction("Wait(Output)");
        ( $screenArray, $screen ) = $self->doAction("Ascii");
    } while ( $screen =~ /press Enter/i );

    if ( $screen !~ /Main Menu/ ) {
        $self->dumpScreen();
        die("ERROR: Login failed\n");
    }
}

sub disconnect {
    my ($self) = @_;

    my $pid      = $self->{pid};
    my $childOut = $self->{childOut};
    my $childIn  = $self->{childIn};

    #press F12, F12=PA(1) + PF(12), F13=PA(2) + PF(1)
    #$self->doAction("PA(1)");
    #$self->doAction("PF(12)");

    $self->doAction(qq(String("90")));
    $self->doAction("Enter");
    $self->doAction("Disconnect");
    $self->doAction("Wait(Output)");
    close($childIn);
    close($childOut);
    waitpid( $pid, 1 );
}

sub execCmd {
    my ( $self, $cmd ) = @_;
    $ENV{TERM} = 'xterm';

    #$self->login();

    $self->doAction("Wait(InputField)");
    $self->doAction(qq(String("$cmd")));
    $self->doAction("Enter");
    $self->doAction("Wait(Output)");

    my $screen = $self->dumpScreen();

    #press F12, F12=PA(1) + PF(12), F13=PA(2) + PF(1)
    $self->doAction("PA(1)");
    $self->doAction("PF(12)");

    #$self->disconnect();

    return $screen;
}

1;
