#!/usr/bin/perl
use strict;

package ServerConf;

use FindBin;
use CWD;
use Crypt::RC4;
use Config::Tiny;

sub new {
    my ( $pkg, %args ) = @_;

    my $confFile = Cwd::abs_path("$FindBin::Script/../../../conf/config.ini");
    my $config   = Config::Tiny->read($confFile);
    my $baseurl  = $config->{server}->{'server.baseurl'};
    my $username = $config->{server}->{'server.username'};
    my $password = $config->{server}->{'server.password'};
    my $passKey  = $config->{server}->{'password.key'};

    my $self = {
        confFile => $confFile,
        baseurl  => $baseurl,
        username => $username,
        password => $password,
        passKey  => $passKey
    };

    bless( $self, $pkg );

    my $MY_KEY = 'c3H002LGZRrseEPc';
    if ( $passKey =~ s/^\{ENCRYPTED\}// ) {
        $self->{passKey} = $self->_rc4_decrypt_hex( $MY_KEY, $passKey );
    }
    if ( $password =~ s/^\{ENCRYPTED\}// ) {
        $self->{password} = $self->_rc4_decrypt_hex( $passKey, $password );
    }

    return $self;
}

sub _rc4_encrypt_hex {
    my ( $self, $key, $data ) = @_;
    return join( '', unpack( 'H*', RC4( $key, $data ) ) );
}

sub _rc4_decrypt_hex {
    my ( $self, $key, $data ) = @_;
    return RC4( $key, pack( 'H*', $data ) );
}

sub decryptPwd {
    my ( $self, $data ) = @_;
    if ( $data =~ s/^\{ENCRYPTED\}// ) {
        return $self->_rc4_decrypt_hex( $self->{passKey}, $data );
    }
    else {
        return $data;
    }
}

1;
