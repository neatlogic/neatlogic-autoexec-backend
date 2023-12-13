#!/usr/bin/perl
use strict;

package WinCmd;
use FindBin;
use SOAP::WinRM;
use Encode::Guess;

use DeployUtils;

sub new {
    my ( $type, $protocol, $host, $port, $user, $pass, $cmd, $isVerbose ) = @_;
    my $self = {};

    $protocol = 'http' if ( not defined($protocol) or $protocol eq '' );

    $self->{protocol}  = $protocol;
    $self->{host}      = $host;
    $self->{port}      = $port;
    $self->{user}      = $user;
    $self->{pass}      = $pass;
    $self->{cmd}       = $cmd;
    $self->{isVerbose} = $isVerbose;

    return bless( $self, $type );
}

sub decodeLineToUtf8 {
    my ( $self, $data ) = @_;

    my $charSet = DeployUtils->guessDataEncoding($data);
    if ( $charSet ne 'UTF-8' ) {
        $data = Encode::encode( "utf-8", Encode::decode( lc($charSet), $data ) );
    }

    return $data;
}

sub exec {
    my ($self) = @_;
    $ENV{LANG}   = 'en_US.UTF8';
    $ENV{LC_ALL} = 'en_US.UTF8';
    my $protocol  = $self->{protocol};
    my $host      = $self->{host};
    my $port      = $self->{port};
    my $user      = $self->{user};
    my $pass      = $self->{pass};
    my $cmd       = $self->{cmd};
    my $isVerbose = $self->{isVerbose};

    # Create SOAP::WinRM Object
    my $winrm = SOAP::WinRM->new(
        protocol => $protocol,
        host     => $host,
        port     => $port,
        username => $user,
        password => $pass
    );

    unless ($winrm) {
        print( "ERROR: Can not connect to windows $user\@$host, cause:" . $winrm->errstr . "\n" );
        return -1;
    }

    my @execute = $winrm->execute( command => [$cmd] );

    if ( $isVerbose == 1 ) {
        my $data = $execute[1];
        if ( $data !~ /^\s*$/ ) {

            #my $enc = guess_encoding( $data, qw/GBK UTF-8/ );
            #if ( ref($enc) ) {
            #    $data = $enc->decode($data);
            #}
            #print( "$data", "\n" );
            print( $self->decodeLineToUtf8($data), "\n" );
        }

        $data = $execute[2];
        if ( $data !~ /^\s*$/ ) {

            #my $enc = guess_encoding( $data, qw/GBK UTF-8/ );
            #if ( ref($enc) ) {
            #    $data = $enc->decode($data);
            #}
            #print( $data, "\n" );
            print( $self->decodeLineToUtf8($data), "\n" );
        }
    }

    my $status = 0;

    if ( defined( $execute[0] ) ) {
        if ( $execute[0] ne 0 ) {
            $status = $execute[0];
            print("ERROR: Run windows remote cmd failed, check the target host WinRM(Windows Remote Management) service.\n");
            my $data = $execute[2];

            if ( $data !~ /^\s*$/ ) {

                #my $enc = guess_encoding( $data, qw/GBK UTF-8/ );
                #if ( ref($enc) ) {
                #    $data = $enc->decode($data);
                #}
                #print( "ERROR: ", $data, "\n" );
                print( 'ERROR: ', $self->decodeLineToUtf8($data), "\n" );
            }
        }
        else {
            $status = 0;
        }
    }
    else {
        $status = -1;
        print( "ERROR: Run cmd failed:" . $winrm->errstr . "\n" );
    }

    return $status;
}

1;
