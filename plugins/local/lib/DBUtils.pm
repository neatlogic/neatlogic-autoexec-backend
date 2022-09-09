#!/usr/bin/perl

package DBUtils;

use strict;
use DBI;
use Encode;

#new BatchJobUtils
#attr:
#	dbType => 'oracle',
#	host => '127.0.0.1',
#	port => 1521,
#	dbName => 'orcl',
#	user => 'oracle',
#	password => 'passwd',
#	sql => 'select xxxx',
sub new {
    my ( $type, $attr ) = @_;

    #DBI would undef the INT signal
    delete( $SIG{INT} );

    if ( not defined( $attr->{interval} ) ) {
        $attr->{interval} = 15;
    }

    if ( not defined( $attr->{port} ) ) {
        $attr->{port} = 1521;
    }

    my $optError;
    if ( not defined( $attr->{dbType} ) ) {
        $optError = $optError . "attr:dbType not defined.\n";
    }
    if ( not defined( $attr->{host} ) ) {
        $optError = $optError . "attr:host not defined.\n";
    }
    if ( not defined( $attr->{dbName} ) ) {
        $optError = $optError . "attr:dbName not defined.\n";
    }
    if ( not defined( $attr->{user} ) ) {
        $optError = $optError . "attr:user not defined.\n";
    }
    if ( not defined( $attr->{password} ) ) {
        $optError = $optError . "attr:password not defined.\n";
    }

    if ( defined($optError) ) {
        die("ERROR: $optError");
    }

    $ENV{LANG}     = 'en_US.UTF-8';
    $ENV{LC_ALL}   = 'en_US.UTF-8';
    $ENV{NLS_LANG} = 'AMERICAN_AMERICA.UTF8';

    my $self = {};
    $self->{$_} = $attr->{$_} for keys(%$attr);

    bless( $self, $type );

    eval { $self->getConnection(); };

    return $self;
}

sub DESTROY {
    my $self = shift;
    $self->close();
}

sub execSql {
    my ( $self, $sql, $bindVars ) = @_;

    if ( not defined($bindVars) and defined( $self->{replaceMap} ) ) {
        $bindVars = $self->{replaceMap};
    }

    if ( defined($bindVars) ) {
        my ( $key, $val );

        foreach $key ( keys(%$bindVars) ) {
            $val = $bindVars->{$key};
            $sql =~ s/#\{$key\}/$val/g;
        }
    }

    my $dbType = $self->{dbType};

    my $dbh = $self->getConnection();
    my $sth = $dbh->prepare($sql);
    $sth->execute();

    my @rows = ();

    my $fieldNames = $sth->{NAME};

    while ( my $row = $sth->fetchrow_hashref() ) {
        my $colCount = scalar(@$fieldNames);
        for ( my $i = 0 ; $i < $colCount ; $i++ ) {
            my $val = DBI::neat( $row->{ $$fieldNames[$i] } );
            $val =~ s/^['"]//;
            $val =~ s/['"]$//;
            $row->{ $$fieldNames[$i] } = $val;

            #$row->{ $$fieldNames[$i] } = Encode::decode( 'UTF-8', $row->{ $$fieldNames[$i] } );
        }
        push( @rows, $row );
    }

    $sth->finish();

    return \@rows;
}

sub getConnection {
    my ($self) = @_;

    my $dbType = $self->{dbType};
    my $dbh    = $self->{connection};

    if ( defined($dbh) ) {
        eval {
            if ( $dbType eq 'oracle' ) {
                $dbh->do("select 1 from dual");
            }
            elsif ( $dbType eq 'mysql' ) {
                $dbh->do("select 1");
            }
        };
        if ($@) {
            undef($dbh);
            $self->{connection} = undef;
        }
    }

    if ( defined($dbh) ) {
        return $dbh;
    }
    else {
        if ( $dbType eq 'oracle' ) {
            $dbh = $self->_getOracleConn();
        }
        elsif ( $dbType eq 'mysql' ) {
            $dbh = $self->_getMysqlConn();
        }
        else {
            die("ERROR: Database $dbType not supported, only support oracle or mysql.\n");
        }

        $self->{connection} = $dbh;
    }

    return $dbh;
}

sub _getOracleConn {
    my ($self) = @_;

    my $host   = $self->{host};
    my $port   = $self->{port};
    my $dbName = $self->{dbName};
    my $user   = $self->{user};
    my $passwd = $self->{password};

    my $dbConnStr = "dbi:Oracle:host=$host;sid=$dbName;port=$port";

    my $dbh;
    eval { $dbh = DBI->connect( $dbConnStr, $user, $passwd, { RaiseError => 1, AutoCommit => 0 } ); };
    if ($@) {
        print("WARN: connect db failed:$@\n");
    }
    my $retryCount = 1;
    while ( not defined($dbh) and $retryCount < 10 ) {
        eval { $dbh = DBI->connect( $dbConnStr, $user, $passwd, { RaiseError => 1, AutoCommit => 0 } ); };
        if ($@) {
            print("WARN: connect db failed:$@\n");
        }
        $retryCount++;

        sleep(10);
    }

    if ( not defined($dbh) ) {
        $self->{connection} = undef;
        die("ERROR: can't connect to database:$!");
    }
    else {
        $self->{connection} = $dbh;
    }

    return $dbh;
}

sub _getMysqlConn {
    my ($self) = @_;

    my $host   = $self->{host};
    my $port   = $self->{port};
    my $dbName = $self->{dbName};
    my $user   = $self->{user};
    my $passwd = $self->{password};

    my $dbConnStr = "DBI:mysql:database=$dbName;host=$host;port=$port";

    my $dbh;
    eval { $dbh = DBI->connect( $dbConnStr, $user, $passwd, { RaiseError => 1, AutoCommit => 0 } ); };
    if ($@) {
        print("WARN: connect db failed:$@\n");
    }

    my $retryCount = 1;
    while ( not defined($dbh) and $retryCount < 10 ) {
        eval { $dbh = DBI->connect( $dbConnStr, $user, $passwd, { RaiseError => 1, AutoCommit => 0 } ); };
        if ($@) {
            print("WARN: connect db failed:$@\n");
        }
        $retryCount++;

        sleep(10);
    }

    if ( not defined($dbh) ) {
        $self->{connection} = undef;
        die("ERROR: can't connect to database:$!");
    }
    else {
        $self->{connection} = $dbh;
    }

    return $dbh;
}

sub close {
    my ($self) = @_;

    my $dbh = $self->{connection};
    if ( defined($dbh) ) {
        eval { $dbh->disconnect(); };
        $self->{connection} = undef;
    }
}

sub dumpData {
    my ( $self, $rowsData, $fieldNamesMap ) = @_;

    if ( defined($fieldNamesMap) ) {
        foreach my $fieldName ( keys(%$fieldNamesMap) ) {
            print( $fieldName, "\t" );
        }
        print("\n");
    }

    foreach my $row (@$rowsData) {
        foreach my $key ( keys(%$row) ) {
            print( $key, ':', $row->{$key}, "\t" );
        }
        print("\n");
    }
}

1;

