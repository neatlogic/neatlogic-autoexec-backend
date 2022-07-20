#!/usr/bin/perl
use strict;

package DBInfo;

use FindBin;

use DeployUtils;

sub new {
    my ( $type, $nodeInfo, $args ) = @_;

    my $self = {
        dbStr             => $nodeInfo->{serviceAddr},
        dbType            => $nodeInfo->{nodeType},
        host              => $nodeInfo->{host},
        port              => $nodeInfo->{port},
        resourceId        => $nodeInfo->{resourceId},
        dbName            => $nodeInfo->{nodeName},
        sid               => $nodeInfo->{nodeName},
        user              => $nodeInfo->{username},
        pass              => $nodeInfo->{password},
        oraWallet         => $args->{oraWallet},
        locale            => $args->{locale},
        fileCharset       => $args->{fileCharset},
        autocommit        => $args->{autocommit},
        version           => $args->{dbVersion},
        args              => $args->{dbArgs},
        ignoreErrors      => $args->{ignoreErrors},
        dbaRole           => $args->{dbaRole},
        db2SqlTerminator  => $args->{db2SqlTerminator},
        db2ProcTerminator => $args->{db2ProcTerminator}
    };

    my $logonTimeout = $args->{logonTimeout};
    if ( not defined($logonTimeout) ) {
        $logonTimeout = 5;
    }

    $logonTimeout = int($logonTimeout);
    if ( $logonTimeout == 0 ) {
        $logonTimeout = 5;
    }

    $self->{logonTimeout} = $logonTimeout;

    $self->{node} = $nodeInfo;

    my $addrsMap    = {};
    my $serviceAddr = $nodeInfo->{serviceAddr};
    if ( defined($serviceAddr) ) {

        #为了兼容IPV6，更改为后面的匹配方式
        # while ( $serviceAddr =~ /(\d+\.\d+\.\d+\.\d+):(\d+)/g ) {
        #     push( @addrs, { host => $1, port => int($2) } );
        # }
        while ( $serviceAddr =~ /([^\/\s,]+):(\d+)/g ) {
            my $host = $1;
            my $port = $2;
            $addrsMap->{"$host:$port"} = { host => $host, port => int($port) };
        }
        my @addrs = values(%$addrsMap);
        $self->{addrs} = \@addrs;
    }

    my $dbName = $args->{dbName};
    if ( defined($dbName) ) {
        $self->{dbName}    = $dbName;
        $self->{sid}       = $dbName;
        $self->{oraWallet} = $dbName;
    }

    my $deployUtils = DeployUtils->new();
    my $password    = $self->{password};
    $password = $deployUtils->decryptPwd($password);
    bless( $self, $type );
    return $self;
}

1;
