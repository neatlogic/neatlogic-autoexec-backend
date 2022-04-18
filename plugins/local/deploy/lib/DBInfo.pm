#!/usr/bin/perl
use strict;

package DBInfo;

use FindBin;

use DeployUtils;

sub new {
    my ( $type, $nodeInfo, $args ) = @_;

    my $self = {
        dbStr        => $nodeInfo->{accessEndpoint},
        dbType       => $nodeInfo->{nodeType},
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

    $self->{node} = $nodeInfo;

    my @addrs;
    my $accessEndpoint = $nodeInfo->{accessEndpoint};
    if ( defined($accessEndpoint) ) {
        while ( $accessEndpoint =~ /(\d+\.\d+\.\d+\.\d+):(\d+)/g ) {
            push( @addrs, { host => $1, port => int($2) } );
        }
        while ( $accessEndpoint =~ /([^\/\s,]+):(\d+)/g ) {
            push( @addrs, { host => $1, port => int($2) } );
        }
        $self->{addrs} = \@addrs;
    }

    my $dbName = $args->{dbName};
    if ( defined($dbName) ) {
        $self->{dbName}    = $dbName;
        $self->{sid}       = $dbName;
        $self->{oraWallet} = $dbName;
    }

    my $password = $self->{password};
    if ( $password =~ s/^\{ENCRYPTED\}// ) {
        $self->{password} = DeployUtils->_rc4_decrypt_hex( $DeployUtils::MY_KEY, $password );
    }
    bless( $self, $type );
    return $self;
}

1;
