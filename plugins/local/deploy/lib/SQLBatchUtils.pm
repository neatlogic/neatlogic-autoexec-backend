#!/usr/bin/perl
use strict;

package SQLBatchUtils;
use FindBin;

use POSIX qw(WNOHANG);
use IO::File;
use File::Path;

use DeployUtils;
use ServerAdapter;

sub new {
    my ( $pkg, %args ) = @_;

    my $self = {
        sqlExtNames => $args{sqlExtNames},
        deployEnv   => $args{deployEnv},
        dirInfo     => $args{dirInfo}
    };

    bless( $self, $pkg );

    my $sqlExtNames = $args{sqlExtNames};
    if ( not defined($sqlExtNames) ) {
        $sqlExtNames = [ 'sql', 'prc', 'pck', 'pkg', 'pkgh', 'pkgb' ];
    }
    $self->{sqlExtNames} = $sqlExtNames;

    return $self;
}

sub getAllSchema {
    my ($self) = @_;

    my $dirInfo = $self->{dirInfo};
    my $distDir = $dirInfo->{distribute};

    my @schemas       = ();
    my @allSchemaDirs = bsd_glob("$distDir/db/*");

    my $schemaName;
    foreach my $schema (@allSchemaDirs) {
        $schemaName = basename($schema);
        if ( -d $schema and $schemaName =~ /^\w+\.\w+$/ ) {
            push( @schemas, $schemaName );
        }
    }

    my @sortedSchemas = sort { $a <=> $b } (@schemas);

    return \@sortedSchemas;
}

sub getSqlFilePathByIdx {
    my ( $self, $indexes, $nameFilter, $isRollback ) = @_;

    if ( not defined($isRollback) ) {
        $isRollback = 0;
    }

    my @idxPatterns = split( /\s*,\s*/, $indexes );

    my $dirInfo = $self->{dirInfo};
    my $distDir = $dirInfo->{distribute};

    my $rootPathLen = length($distDir) + 4;

    my $idxFileMap  = {};
    my @allSqlFiles = ();
    for my $idxPattern (@idxPatterns) {
        for my $idxFile ( bsd_glob("$distDir/db/$idxPattern") ) {
            if ( defined( $idxFileMap->{$idxFile} ) ) {
                next;
            }
            else {
                $idxFileMap->{$idxFile} = 1;
            }

            my $idxDir = dirname($idxFile);
            my $idxFh  = IO::File->new("<$idxFile");
            if ( defined($idxFh) ) {
                my $isFirstLine = 0;
                my $line;
                while ( $line = $idxFh->getline() ) {
                    if ( $isFirstLine == 0 ) {

                        #cut Bom header in index file
                        $isFirstLine = 1;
                        $line =~ s/^\xef\xbb\xbf//;
                    }

                    $line =~ s/^\s*//;
                    $line =~ s/\s*$//;
                    $line =~ s/^\@//;
                    if ( $line !~ /^--/ and $line !~ /^#/ ) {
                        $line =~ s/^\@//;
                        my $fileName = substr( File::Spec->canonpath("$idxDir/$line"), $rootPathLen );
                        my $idxFileName = substr( $idxFile, $rootPathLen );
                        if ( $fileName eq $idxFileName ) {
                            next;
                        }

                        if ( defined($nameFilter) and $nameFilter ne '' ) {
                            if ( $isRollback == 1 ) {
                                if ( $fileName =~ /\/$nameFilter\// and $fileName =~ /\/rollback\//i ) {
                                    push( @allSqlFiles, $fileName );
                                }
                            }
                            else {
                                if ( $fileName =~ /\/$nameFilter\// and $fileName !~ /\/rollback\//i ) {
                                    push( @allSqlFiles, $fileName );
                                }
                            }
                        }
                        else {
                            if ( $isRollback == 1 ) {
                                if ( $fileName =~ /\/rollback\//i ) {
                                    push( @allSqlFiles, $fileName );
                                }
                            }
                            else {
                                if ( $fileName !~ /\/rollback\//i ) {
                                    push( @allSqlFiles, $fileName );
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    return \@allSqlFiles;
}

sub getSqlFilePath {
    my ( $self, $nameFilter, $isRollback ) = @_;

    if ( not defined($isRollback) ) {
        $isRollback = 0;
    }

    sub sqlSort {
        my $aSql = basename($a);
        my $bSql = basename($b);

        my @aSeqs = ();
        my @bSeqs = ();

        if ( $aSql =~ /^(\d[\d\.]*)/ ) {
            @aSeqs = split( '\.', $1 );
        }

        if ( $bSql =~ /^(\d[\d\.]*)/ ) {
            @bSeqs = split( '\.', $1 );
        }

        my $aLen = scalar(@aSeqs);
        my $bLen = scalar(@bSeqs);

        my $cmpRet = 0;

        my ( $i, $aSeq, $bSeq );
        if ( $aLen > 0 && $bLen > 0 ) {
            for ( $i = 0 ; $i < $aLen ; $i++ ) {
                $aSeq = int( $aSeqs[$i] );
                $bSeq = int( $bSeqs[$i] );

                if ( $aSeq > $bSeq ) {
                    $cmpRet = 1;
                    last;
                }
                elsif ( $aSeq < $bSeq ) {
                    $cmpRet = -1;
                    last;
                }
            }

            if ( $cmpRet eq 0 ) {
                if ( $aLen eq $bLen ) {
                    $cmpRet = $a cmp $b;
                }
                elsif ( $aLen > $bLen ) {
                    $cmpRet = -1;
                }
                else {
                    $cmpRet = 1;
                }
            }
        }
        elsif ( $aLen eq 0 and $bLen eq 0 ) {
            $cmpRet = $a cmp $b;
        }
        elsif ( $aLen eq 0 ) {
            $cmpRet = -1;
        }
        else {
            $cmpRet = 1;
        }

        return $cmpRet;
    }

    my $dirInfo = $self->{dirInfo};
    my $distDir = $dirInfo->{distribute};

    my $schemas = $self->getAllSchema();

    my $sqlExtNames = $self->{sqlExtNames};
    my %sqlExtNamesMap;
    foreach my $sqlExtName (@$sqlExtNames) {
        $sqlExtNamesMap{$sqlExtName} = 1;
    }

    my @allSqlFiles = ();
    for my $schema (@$schemas) {
        chdir("$distDir/db");
        find(
            {
                wanted => sub {
                    my $fileName = $File::Find::name;
                    if ( -f "$distDir/db/$fileName" ) {
                        my $extName = lc( substr( $fileName, rindex( $fileName, '.' ) + 1 ) );
                        if ( exists( $sqlExtNamesMap{$extName} ) ) {
                            if ( defined($nameFilter) and $nameFilter ne '' ) {
                                if ( $isRollback == 1 ) {
                                    if ( $fileName =~ /\/$nameFilter\// and $fileName =~ /\/rollback\//i ) {
                                        push( @allSqlFiles, $fileName );
                                    }
                                }
                                else {
                                    if ( $fileName =~ /\/$nameFilter\// and $fileName !~ /\/rollback\//i ) {
                                        push( @allSqlFiles, $fileName );
                                    }
                                }
                            }
                            else {
                                if ( $isRollback == 1 ) {
                                    if ( $fileName =~ /\/rollback\//i ) {
                                        push( @allSqlFiles, $fileName );
                                    }
                                }
                                else {
                                    if ( $fileName !~ /\/rollback\//i ) {
                                        push( @allSqlFiles, $fileName );
                                    }
                                }
                            }
                        }
                    }
                },
                follow => 1
            },
            $schema
        );
    }

    my @sortedSqlFiles = sort sqlSort @allSqlFiles;

    return \@sortedSqlFiles;
}

sub getRunRoundSets {
    my ( $self, $sqlFiles, $parallelCount ) = @_;

    my $parCount = 0;
    my ( $prefix, @runSqlSet, @runSqlSets );
    my $oneSqlFile;
    foreach $oneSqlFile (@$sqlFiles) {
        my $myPrefix;
        my $sqlName = substr( $oneSqlFile, rindex( $oneSqlFile, '/' ) + 1 );
        if ( $sqlName =~ /^([\d\.]+)/ ) {
            $myPrefix = $1;
        }

        $parCount++;

        if ( defined($myPrefix) and $myPrefix eq $prefix and $parCount <= $parallelCount ) {
            push( @runSqlSet, $oneSqlFile );
        }
        else {
            if ( scalar(@runSqlSet) > 0 ) {
                my @myRunSqlSet = @runSqlSet;
                push( @runSqlSets, \@myRunSqlSet );
            }

            $parCount  = 1;
            @runSqlSet = ();
            push( @runSqlSet, $oneSqlFile );
            $prefix = $myPrefix;
        }
    }
    if ( scalar(@runSqlSet) > 0 ) {
        push( @runSqlSets, \@runSqlSet );
    }

    return \@runSqlSets;
}

1;
