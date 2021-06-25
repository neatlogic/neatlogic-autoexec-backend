#!/usr/bin/perl
use FindBin;

#use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
#use lib "$FindBin::Bin/../lib";

package DBInfo;

use strict;

sub new {
    my ( $type, $nodeInfo ) = @_;
    my $self = {
        dbStr        => $nodeInfo->{accessEndpoing},
        dbType       => $nodeInfo->{nodeType},
        host         => $nodeInfo->{host},
        port         => $nodeInfo->{port},
        dbName       => $nodeInfo->{nodeName},
        sid          => $nodeInfo->{nodeName},
        user         => $nodeInfo->{username},
        pass         => $nodeInfo->{password},
        oraWallet    => undef,
        locale       => undef,
        fileCharset  => undef,
        autocommit   => 0,
        version      => undef,
        args         => undef,
        ignoreErrors => 0
    };

    my @addrs;
    while ( $self->{dbStr} =~ /([\w\.]+:\d+)/g ) {
        push( @addrs, $1 );
    }
    $self->{addrs} = \@addrs;

    bless( $self, $type );
    return $self;
}

1;
