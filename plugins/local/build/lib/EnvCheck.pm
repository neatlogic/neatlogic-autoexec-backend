#!/usr/bin/perl
use strict;

package EnvCheck;

use FindBin;
use Cwd 'realpath';
use File::Glob qw(bsd_glob);

use DeployUtils;
use TagentClient;
use SQLFileRunner;

sub checkDBSchemaPassByClient {
    my ( $envPath, $version ) = @_;
    my $deploysysHome = realpath("$FindBin::Bin/..");

    my $envInfo = ENVPathInfo::parse( $envPath, $version );
    my $runBatch = new RunBatch( $envPath, $version );
    my $allschemas = $runBatch->getAllSchema();

    my $dbStatus = 1;

    foreach my $schema (@$allschemas) {
        my @dbDescs   = split( '\.', $schema );
        my $dbName    = $dbDescs[0];
        my $userAlias = $dbDescs[1];

        print("INFO: database $schema connecting...\n");
        my $sqlRunner = SQLFileRunner->new( envPathInfo => $envInfo, dbName => $dbName, userAlias => $userAlias );

        my $connected = $sqlRunner->test();
        if ( $connected == 0 ) {
            $dbStatus = 0;
        }
    }

    return $dbStatus;
}

sub checkDBPassByIpPort {
    my ( $dbType, $host, $port, $dbName, $user, $pass ) = @_;

    my $dbStatus = 1;

    my $connected = SQLFileRunner::testByIpPort( $dbType, $host, $port, $dbName, $user, $pass );
    if ( $connected == 0 ) {
        $dbStatus = 0;
    }

    return $dbStatus;
}

1;

