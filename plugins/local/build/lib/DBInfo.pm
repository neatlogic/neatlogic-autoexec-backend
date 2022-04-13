#!/usr/bin/perl
use FindBin;

#use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
#use lib "$FindBin::Bin/../lib";

package DBInfo;

use strict;

sub new {
    my ( $type, $nodeInfo, $args ) = @_;

    my $self = {
        dbStr  => $nodeInfo->{accessEndpoint},
        dbType => $nodeInfo->{nodeType},

        #dbType       => 'mysql',
        host         => $nodeInfo->{host},
        port         => $nodeInfo->{port},
        nodeId       => $nodeInfo->{nodeId},
        resourceId   => $nodeInfo->{resourceId},
        dbName       => $nodeInfo->{nodeName},
        sid          => $nodeInfo->{nodeName},
        user         => $nodeInfo->{username},
        pass         => $nodeInfo->{password},
        oraWallet    => $args->{oraWallet},
        locale       => $args->{locale},
        fileCharset  => $args->{fileCharset},
        autocommit   => $args->{autocommit},
        version      => $args->{dbVersion},
        args         => $args->{dbArgs},
        ignoreErrors => $args->{ignoreErrors}
    };

    my @addrs;
    while ( $self->{dbStr} =~ /([\w\.]+:\d+)/g ) {
        push( @addrs, $1 );
    }
    $self->{addrs} = \@addrs;

    my $dbName = $args->{dbName};
    if ( defined($dbName) ) {
        $self->{dbName}    = $dbName;
        $self->{sid}       = $dbName;
        $self->{oraWallet} = $dbName;
    }

    bless( $self, $type );
    return $self;
}

1;