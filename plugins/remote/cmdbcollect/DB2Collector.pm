#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package DB2Collector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

sub getConfig {
    return {
        seq      => 100,
        regExps  => ['\bdb2sysc\b'],
        psAttrs  => { COMM => 'db2sysc' },
        envAttrs => { DB2_HOME => undef, DB2INSTANCE => undef }
    };
}

sub getMemInfo {
    my ( $self, $insInfo ) = @_;
    my $utils = $self->{collectUtils};

    # [db2inst1@sit-asm-123 tmp]$ db2pd -dbptnmem

    # Database Member 0 -- Active -- Up 0 days 05:54:57 -- Date 2021-07-06-20.28.13.373391

    # Database Member Memory Controller Statistics

    # Controller Automatic: Y
    # Memory Limit:         6647900 KB
    # Current usage:        140800 KB
    # HWM usage:            608832 KB
    # Cached memory:        7680 KB

    # Individual Memory Consumers:

    # Name             Mem Used (KB) HWM Used (KB) Cached (KB)
    # ========================================================
    # DBMS-db2inst1           106240        106240        7680
    # FMP_RESOURCES            22528         22528           0
    # PRIVATE                  12032         12544           0
    my $memLines   = $self->getCmdOutLines( 'db2pd -dbptnmem', $insInfo->{OS_USER} );
    my $linesCount = scalar(@$memLines);
    my $idx        = 0;
    for ( my $idx = 0 ; $idx < $linesCount ; $idx++ ) {
        my $line = $$memLines[$idx];
        if ( $line =~ /Memory Limit:\s*(\d+)\s*(KB)/ ) {
            $insInfo->{MEMORY_LIMIT} = $utils->getMemSizeFromStr("$1$2");
        }
        elsif ( $line =~ /Current usage:\s*(\d+)\s*(KB)/ ) {
            $insInfo->{MEMORY_CURRENT_USAGE} = $utils->getMemSizeFromStr("$1$2");
        }
        elsif ( $line =~ /HWM usage:\s*(\d+)\s*(KB)/ ) {
            $insInfo->{MEMORY_HWM_USAGE} = $utils->getMemSizeFromStr("$1$2");
        }
        elsif ( $line =~ /Cached memory:\s*(\d+)\s*(KB)/ ) {
            $insInfo->{CACHED_MEMORY} = $utils->getMemSizeFromStr("$1$2");
        }
        elsif ( $line =~ /=====================/ ) {
            last;
        }
    }

    my $dbMemory = {};
    for ( $idx++ ; $idx < $linesCount ; $idx++ ) {
        my $line = $$memLines[$idx];
        $line =~ s/^\s*|\s*$//g;
        my @idvMemInfos = split( /\s+/, $line );
        my $info = {
            DB_NAME  => $idvMemInfos[0],
            MEM_USED => int( $idvMemInfos[1] * 100 / 1024 / 1024 + 0.5 ) / 100,
            HWM_USED => int( $idvMemInfos[2] * 100 / 1024 / 1024 + 0.5 ) / 100,
            CACHED   => int( $idvMemInfos[3] * 100 / 1024 / 1024 + 0.5 ) / 100
        };
        $dbMemory->{ $idvMemInfos[0] } = $info;
    }

    return $dbMemory;
}

sub getConnManInfo {
    my ( $self, $insInfo ) = @_;

    #db2 get dbm cfg
    #这里包含了DB2的大部分设置属性
    my $dbmLines = $self->getCmdOutLines( 'db2 get dbm cfg', $insInfo->{OS_USER} );
    my $linesCount = scalar(@$dbmLines);
    for ( my $idx = 0 ; $idx < $linesCount ; $idx++ ) {
        my $line = $$dbmLines[$idx];
        if ( $line =~ /\((\w+)\)\s=\s(.*?)$/ ) {
            $insInfo->{ uc($1) } = $2;
        }
    }
}

sub getTablespaceInfo {
    my ( $self, $insInfo, $dbName ) = @_;

    #db2 connect to test2 && db2pd -tablespace -db test2
}

sub getTCPInfo {
    my ( $self, $insInfo ) = @_;

    #TCP/IP Service name                          (SVCENAME) = DB2_db2inst1
    #SSL service name                         (SSL_SVCENAME) =
    my $svcName;
    my $sslSvcName;
    my $svcDef = $self->getCmdOutLines( 'db2 get dbm cfg|grep SVCENAME', $insInfo->{OS_USER} );
    foreach my $line (@$svcDef) {
        if ( $line =~ /\(SVCENAME\)\s+=\s+(.*)\s*$/ ) {
            $svcName = $1;
        }
        elsif ( $line =~ /\(SSL_SVCENAME\)\s+=\s+(.*)\s*$/ ) {
            $sslSvcName = $1;
        }
    }

    my @ports;
    my $port;
    my $sslPort;
    if ( $svcName =~ /^\d+$/ ) {
        $port = $svcName;
    }
    if ( $sslSvcName =~ /^\d+$/ ) {
        $sslPort = $sslSvcName;
    }

    if ( not defined($port) ) {
        my $cmd = qq{grep "$svcName" /etc/services};
        if ( defined($sslSvcName) and $sslSvcName ne '' ) {
            $cmd = qq{grep "$svcName\|$sslSvcName" /etc/services};
        }
        my $portDef = $self->getCmdOutLines($cmd);
        foreach my $line (@$portDef) {
            if ( $line =~ /^$svcName\s+(\d+)\/tcp/ ) {
                $port = $1;
            }
            elsif ( $line =~ /^$sslSvcName\s+(\d+)\/tcp/ ) {
                $sslPort = $1;
            }
        }
    }

    if ( defined($port) ) {
        push( @ports, $port );
    }
    else {
        print("WARN: DB2 service $svcName not found in /etc/services.\n");
        $port = '50000';
    }
    if ( defined($sslPort) ) {
        push( @ports, $port );
    }

    $insInfo->{PORT}           = $port;
    $insInfo->{SSL_PORT}       = $sslPort;
    $insInfo->{MON_PORT}       = $port;
    $insInfo->{ADMIN_PORT}     = $port;
    $insInfo->{ADMIN_SSL_PORT} = $sslPort;
    $insInfo->{PORTS}          = \@ports;
}

sub getDBInfos {
    my ( $self, $insInfo, $dbMemory ) = @_;

    my $user  = $insInfo->{OS_USER};
    my $utils = $self->{collectUtils};

    # Database 1 entry:

    #  Database alias                       = DB1
    #  Database name                        = DB1
    #  Local database directory             = /home/db2inst1
    #  Database release level               = d.00
    #  Comment                              =
    #  Directory entry type                 = Indirect
    #  Catalog database partition number    = 0
    #  Alternate server hostname            =
    #  Alternate server port number         =
    my @dbNames = ();
    my @dbTypes = ();
    my @dbDirs  = ();
    my $dbDef   = $self->getCmdOutLines( 'db2 list db directory', $user );
    foreach my $line (@$dbDef) {
        if ( $line =~ /^\s*Database name\s+=\s+(.*)$/ ) {
            push( @dbNames, $1 );
        }
        elsif ( $line =~ /^\s*Directory entry type\s+=\s+(.*)$/ ) {
            push( @dbTypes, $1 );
        }
        elsif ( $line =~ /^\s*Local database directory\s+=\s+(.*)$/ ) {
            push( @dbDirs, $1 );
        }
    }

    my @localDbs;
    for ( my $i = 0 ; $i < scalar(@dbTypes) ; $i++ ) {
        my $dbType = $dbTypes[$i];
        if ( $dbType !~ /remote/i ) {
            my $dbInfo = $dbMemory->{ $dbNames[$i] };
            $dbInfo->{NAME}         = $dbNames[$i];
            $dbInfo->{DB_NAME}      = $dbNames[$i];
            $dbInfo->{PRIMARY_IP}   = $insInfo->{MGMT_IP};
            $dbInfo->{DB_DIRECTORY} = $dbDirs[$i];    #TODO: 需确认这个属性的意义
            push( @localDbs, $dbInfo );
        }
    }
    $insInfo->{DATABASES} = \@localDbs;

    #获取所有子DB的关联用户
    my @allDbUsers = ();
    foreach my $db (@localDbs) {
        my $dbName = $db->{DB_NAME};

        # [db2inst1@sit-asm-123 ~]$ db2 "select distinct cast((grantee) as char(20)) as GRANTEE from syscat.tabauth"

        # GRANTEE
        # --------------------
        # DB2INST1
        # PUBLIC

        # 2 record(s) selected.
        my $selCmd = qq{db2 connect to "$dbName" && db2 "select distinct cast((grantee) as char(20)) as GRANTEE from syscat.tabauth" && db2 disconnect current};

        my $infoLines = $self->getCmdOutLines( $selCmd, $user );
        my $linesCount = scalar(@$infoLines);

        my $idx  = 0;
        my $line = $$infoLines[$idx];
        while ( $line !~ /^------/ ) {
            $idx++;
            $line = $$infoLines[$idx];
        }

        for ( $idx++ ; $idx < $linesCount ; $idx++ ) {
            my $line = $$infoLines[$idx];
            if ( $line =~ /record\(s\) selected\./ ) {
                last;
            }
            $line =~ s/^\s*|\s*$//g;
            if ( $line ne '' ) {
                push( @allDbUsers, { NAME => $line } );
            }
        }
        $insInfo->{USERS} = \@allDbUsers;

        #获取所有子DB的Table space信息
        my $tblspaceCmd = qq{db2 connect to "$dbName" && db2pd -d "$dbName" -tablespace && db2 disconnect current};
        my $status;
        ( $status, $infoLines ) = $self->getCmdOutLines( $tblspaceCmd, $user );

        if ( $status == 0 ) {
            $linesCount = scalar(@$infoLines);
            my $tableSpaceConf = {};

            #skip掉前面没用的文本行
            $idx = 0;
            my $line = $$infoLines[$idx];
            while ( $idx < $linesCount and $line !~ /^Address            / ) {
                $idx++;
                $line = $$infoLines[$idx];
            }

            #第一个子表，抽取name和pageSize属性
            $idx++;
            $line = $$infoLines[$idx];
            while ( $idx < $linesCount and $line !~ /^Address            / ) {
                my @fields = split( /\s+/, $line );
                if ( scalar(@fields) == 16 ) {
                    $tableSpaceConf->{ $fields[1] } = {
                        NAME       => $fields[-1],
                        PAGE_SIZE  => int( $fields[4] ),
                        DATA_FILES => []
                    };
                }
                $idx++;
                $line = $$infoLines[$idx];
            }

            #第二个子表
            $idx++;
            $line = $$infoLines[$idx];
            while ( $idx < $linesCount and $line !~ /^Address            / ) {
                my @fields = split( /\s+/, $line );
                if ( scalar(@fields) == 14 ) {
                    my $spcInfo = $tableSpaceConf->{ $fields[1] };

                    my $totalPages   = int( $fields[2] );
                    my $useablePages = int( $fields[3] );
                    my $usedPages    = int( $fields[4] );
                    my $freePages    = int( $fields[6] );
                    my $pageSize     = $spcInfo->{PAGE_SIZE};

                    $spcInfo->{TOTAL} = sprintf( '%.4f', $totalPages * $pageSize / 1024 / 1024 / 1024 + 0.00005 ) + 0.0;
                    $spcInfo->{USED}  = sprintf( '%.4f', $usedPages * $pageSize / 1024 / 1024 / 1024 + 0.00005 ) + 0.0;
                    $spcInfo->{FREE}  = sprintf( '%.4f', $freePages * $pageSize / 1024 / 1024 / 1024 + 0.00005 ) + 0.0;

                    $spcInfo->{FREE_PCT} = sprintf( '%.2f', $freePages / $useablePages * 100 + 0.005 ) + 0.0;
                    $spcInfo->{USED_PCT} = sprintf( '%.2f', $usedPages / $useablePages * 100 + 0.005 ) + 0.0;
                }
                $idx++;
                $line = $$infoLines[$idx];
            }

            #第三个子表
            $idx++;
            $line = $$infoLines[$idx];
            while ( $idx < $linesCount and $line !~ /^Address            / ) {
                my @fields = split( /\s+/, $line );
                if ( scalar(@fields) == 10 ) {
                    my $spcInfo = $tableSpaceConf->{ $fields[1] };
                    $spcInfo->{AUTOEXTENSIBLE} = $fields[3];
                }
                $idx++;
                $line = $$infoLines[$idx];
            }

            #第四个子表
            $idx++;
            $line = $$infoLines[$idx];
            while ( $idx < $linesCount and $line !~ /^Address            / ) {
                $idx++;
                $line = $$infoLines[$idx];
            }

            #第五个子表
            $idx++;
            $line = $$infoLines[$idx];
            while ( $idx < $linesCount and $line !~ /^Address            / ) {
                my @fields = split( /\s+/, $line );
                if ( scalar(@fields) == 9 ) {
                    my $spcInfo  = $tableSpaceConf->{ $fields[1] };
                    my $filePath = $fields[-1];
                    my $fileSize = -s $filePath;
                    $fileSize = int( $fileSize * 100 / 1024 / 1024 / 1024 ) / 100;
                    my $dataFileInfo = {};
                    $dataFileInfo->{FILE_NAME} = $filePath;
                    $dataFileInfo->{SIZE}      = $fileSize;
                    my $dataFiles = $spcInfo->{DATA_FILES};

                    if ( not defined($dataFiles) ) {
                        $dataFiles = [];
                        $spcInfo->{DATA_FILES} = @$dataFiles;
                    }
                    push( @$dataFiles, $dataFileInfo );
                }
                $idx++;
                $line = $$infoLines[$idx];
            }

            my @tableSpaces = values(%$tableSpaceConf);
            $db->{TABLE_SPACESES} = \@tableSpaces;
        }
    }
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    my $insInfo  = {};
    $insInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');

    my $db2InstUser = $procInfo->{USER};

    my $db2InstArray = $self->getCmdOutLines( 'db2ilist', $db2InstUser );
    my @db2Insts = grep { $_ !~ /mail/i } @$db2InstArray;
    if ( scalar(@db2Insts) == 0 ) {
        print("WARN: No db2 instance found.\n");
        return;
    }
    chomp(@db2Insts);

    my $version;
    my $user = $db2Insts[0];
    my $verInfo = $self->getCmdOut( 'db2level', $user );
    if ( $verInfo =~ /"DB2\s+(v\S+)"/ ) {
        $version = $1;
        $insInfo->{VERSION} = $version;

        #$insInfo->{DB_ID}   = $version;    #TODO：原来的，为什么DB_ID是version？
    }
    else {
        print("WARN: No db2 instance found, can not execute command:db2level.\n");
        return;
    }

    my $envMap = $procInfo->{ENVIRONMENT};
    $insInfo->{DB2_HOME}     = $envMap->{DB2_HOME};
    $insInfo->{INSTALL_PATH} = $envMap->{DB2_HOME};
    $insInfo->{DB2LIB}       = $envMap->{DB2LIB};

    $insInfo->{SERVER_NAME}   = $procInfo->{HOST_NAME};
    $insInfo->{INSTANCE_NAME} = $user;
    $insInfo->{OS_USER}       = $user;

    $self->getTCPInfo($insInfo);

    #$self->getConnManInfo($insInfo);
    my $dbMemory = $self->getMemInfo($insInfo);
    $self->getDBInfos( $insInfo, $dbMemory );

    return $insInfo;
}

1;
