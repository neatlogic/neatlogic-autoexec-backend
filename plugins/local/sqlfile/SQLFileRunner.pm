#!/usr/bin/perl

use FindBin;

#use lib $FindBin::Bin;
#use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";

package SQLFileRunner;

use strict;
use POSIX qw(strftime);
use IO::File;
use Cwd;
use Digest::MD5;
use File::Path;
use File::Basename;
use Getopt::Long;
use JSON;
use DBInfo;
use AutoExecUtils;
use Utils;

use SQLFileStatus;

sub new {
    my ( $type, %args ) = @_;

    my $self = {
        dbNode       => $args{dbNode},
        sqlFiles     => $args{sqlFiles},
        istty        => $args{istty},
        isForce      => $args{isForce},
        isDryRun     => $args{isDryRun},
        dbVersion    => $args{dbVersion},
        dbArgs       => $args{dbArgs},
        oraWallet    => $args{oraWallet},
        locale       => $args{locale},
        fileCharset  => $args{fileCharset},
        autocommit   => $args{autocommit},
        ignoreErrors => $args{ignoreErrors}
    };

    bless( $self, $type );

    my ( $jobPath, $phaseName ) = $self->_initDir();

    $self->{jobPath}   = $jobPath;
    $self->{phaseName} = $phaseName;

    my $dbInfo = DBInfo->new( $self->{dbNode}, \%args );
    $self->{dbInfo}     = $dbInfo;
    $self->{sqlFileDir} = "$jobPath/sqlfile/$phaseName";
    $self->{logFileDir} = "$jobPath/log/$phaseName/$dbInfo->{host}-$dbInfo->{port}-$dbInfo->{resourceId}";

    return $self;
}

sub _initDir {
    my ($self) = @_;

    my $hasError = 0;
    my $jobPath  = $ENV{AUTOEXEC_WORK_PATH};
    if ( not defined($jobPath) or $jobPath eq '' ) {
        $jobPath = getcwd();
    }
    my $phaseName = $ENV{AUTOEXEC_PHASE_NAME};
    if ( not defined($phaseName) or $phaseName eq '' ) {
        $phaseName = 'sql-file';
    }

    #sqlfile, log, status
    #jobpath/
    #|-- file
    #|   |-- 1.sql
    #|   `-- 2.sql
    #|-- log
    #|   `-- phase-run
    #|       `-- 192.168.0.26-3306-bsm
    #|           |-- 2.sql.hislog
    #|           |   |-- 20210625-163515-failed-anonymous.txt
    #|           |   |-- 20210625-163607-failed-anonymous.txt
    #|           |   `-- 20210625-164543-failed-anonymous.txt
    #|           `-- 2.sql.txt
    #|-- sqlfile
    #|   `-- phase-run
    #|       `-- 2.sql
    #`-- status
    #    `-- phase-run
    #            `-- 192.168.0.26-3306-bsm
    #                        `-- 2.sql.txt

    if ( not -e "$jobPath/sqlfile/$phaseName" ) {
        mkpath("$jobPath/sqlfile/$phaseName");
        my $err = $!;
        if ( not -e "$jobPath/sqlfile/$phaseName" ) {
            $hasError = 1;
            print("ERROR: Create dir '$jobPath/sqlfile/$phaseName' failed $err\n");
        }
    }

    if ( not -e "$jobPath/log/$phaseName" ) {
        mkpath("$jobPath/log/$phaseName");
        my $err = $!;
        if ( not -e "$jobPath/log/$phaseName" ) {
            $hasError = 1;
            print("ERROR: Create dir '$jobPath/log/$phaseName' failed $err\n");
        }
    }

    if ( not -e "$jobPath/status/$phaseName" ) {
        mkpath("$jobPath/status/$phaseName");
        my $err = $!;
        if ( not -e "$jobPath/status/$phaseName" ) {
            $hasError = 1;
            print("ERROR: Create dir '$jobPath/status/$phaseName' failed $err\n");
        }
    }

    if ( $hasError == 1 ) {
        exit(2);
    }

    return ( $jobPath, $phaseName );
}

sub execOneSqlFile {
    my ( $self, $sqlFile, $sqlFileStatus ) = @_;

    Utils::sigHandler(
        'TERM', 'INT', 'HUP', 'ABRT',
        sub {
            $sqlFileStatus->_loadStatus();
            my $status = $sqlFileStatus->{status};
            if ( $status->{status} eq 'waitInput' ) {
                my $interact = $status->{interact};
                if ( $interact and $interact->{pipeFile} and -e $interact->{pipeFile} ) {
                    unlink( $interact->{pipeFile} );
                }
            }
            $sqlFileStatus->updateStatus( status => 'aborted', warnCount => $ENV{WARNING_COUNT}, endTime => time() );
            return -1;
        }
    );

    my $hasError = 0;

    my $dbNode    = $self->{dbNode};
    my $phaseName = $self->{phaseName};
    my $dbInfo    = $self->{dbInfo};

    my $logFileDir = $self->{logFileDir};
    my $sqlDir     = dirname($sqlFile);
    if ( not -e "$logFileDir/$sqlDir" ) {
        mkpath("$logFileDir/$sqlDir");
    }

    my $logFileDir = $self->{logFileDir};
    if ( not -e $logFileDir ) {
        if ( not mkdir($logFileDir) ) {
            print("ERROR: Create log directory $logFileDir failed $!\n");
        }
    }

    my $logFilePath = "$logFileDir/$sqlFile.txt";
    my $hisLogDir   = "$logFileDir/$sqlFile.hislog";
    if ( not -e $hisLogDir ) {
        if ( not mkdir($hisLogDir) ) {
            $hasError = 1;
            print("ERROR: Create dir $hisLogDir failed $!\n");
        }
    }
    my $dateTimeStr    = strftime( "%Y%m%d-%H%M%S", localtime() );
    my $hisLogName     = "$dateTimeStr-running-$ENV{AUTOEXEC_USER}.txt";
    my $hisLogFilePath = "$hisLogDir/$hisLogName";
    my $logFH          = IO::File->new(">$logFilePath");
    $logFH->autoflush(1);
    link( $logFilePath, $hisLogFilePath );

    END {
        if ( defined($sqlFileStatus) ) {
            my $endStatus     = $sqlFileStatus->getStatusValue('status');
            my $newHisLogName = $hisLogName;
            $newHisLogName =~ s/-running-/-$endStatus-/;
            my $newHisLogPath = "$hisLogDir/$newHisLogName";
            rename( $hisLogFilePath, $newHisLogPath );
        }
        if ( defined($logFH) ) {
            $logFH->close();
        }
    }

    #redirect stdout and rotate log file to his log
    if ( not $self->{istty} ) {
        open( STDOUT, sprintf( ">&=%d", $logFH->fileno() ) );
        open( STDERR, sprintf( ">&=%d", $logFH->fileno() ) );
    }
    select(STDERR);
    $| = 1;
    select(STDOUT);
    $| = 1;

    my $dbType = uc( $dbInfo->{dbType} );
    my $dbName = $dbInfo->{dbName};

    my $handlerName = uc($dbType) . 'SQLRunner';
    my $requireName = $handlerName . '.pm';

    my $sqlFilePath = "$self->{sqlFileDir}/$sqlFile";
    my $charSet     = Utils::guessEncoding($sqlFilePath);

    #TODO: auto detect file charset.

    print("#***************************************\n");
    print("# JOB_ID=$ENV{AUTOEXEC_JOBID}\n");
    print("# FILE=$sqlFile\n");
    print("# MD5=$sqlFileStatus->{status}->{md5}\n");
    print( "# $dbType/$dbName Begin\@" . strftime( "%Y/%m/%d %H:%M:%S", localtime() ) . "\n" );
    print("#***************************************\n\n");

    my $startTime = time();
    my $spawn;

    if ( $self->{isDryRun} == 1 ) {
        print("INFO: Dry run sql $sqlFilePath.\n");
        $sqlFileStatus->updateStatus( interact => undef, status => 'running', startTime => time(), endTime => undef );
    }
    else {
        my $handler;
        eval {
            print( "INFO: Try to use SQLRunner " . uc($dbType) . ".\n" );
            require $requireName;

            $handler = $handlerName->new( $dbInfo, $sqlFilePath, $charSet, $logFilePath );
        };
        if ($@) {
            $hasError = 1;
            print("ERROR: $@\n");
        }

        if ( defined($handler) ) {
            $spawn = $handler->{spawn};
        }

        if ( defined($spawn) ) {
            $spawn->log_stdout(0);
            $spawn->log_file(
                sub {
                    if ( $handler->{hasLogon} == 1 ) {
                        my $content = shift;
                        $content =~ s/\x0D//g;
                        print($content);
                    }
                }
            );
        }

        $sqlFileStatus->updateStatus( interact => undef, status => 'running', startTime => time(), endTime => undef );
        eval { $hasError = $handler->run(); };
        if ($@) {
            print("ERROR: Unknow error ocurred.\n$@\n");
            $hasError = 1;
        }
    }

    if ( $hasError == 0 ) {
        if ( defined($spawn) ) {
            if ( defined( $spawn->exitstatus() ) and $spawn->exitstatus() == 0 ) {
                print("\nFINEST:execute sql:$sqlFile success.\n");
            }
            else {
                print("\nERROR:execute sql:$sqlFile failed, check log for detail.\n");
                $hasError = 1;
            }
        }
        else {
            print("\nFINEST:execute sql:$sqlFile success.\n");
        }
    }
    else {
        print("\nERROR:execute sql:$sqlFile failed, check log for detail.\n");
        $hasError = 1;
    }

    if ( $hasError == 0 ) {
        $sqlFileStatus->updateStatus( status => 'succeed', warnCount => $ENV{WARNING_COUNT}, endTime => time() );
    }
    else {
        $sqlFileStatus->updateStatus( status => 'failed', warnCount => $ENV{WARNING_COUNT}, endTime => time() );
    }

    my $consumeTime = time() - $startTime;
    print("\n=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=\n");
    print( "= End\@" . strftime( "%Y/%m/%d %H:%M:%S", localtime() ) . "\n" );
    print("= Elapsed time: $consumeTime seconds.\n");
    print("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=\n\n");

    return $hasError;
}

sub _checkAndDelBom {
    my ( $self, $filePath ) = @_;
    my $fhRead  = IO::File->new("+<$filePath");
    my $fhWrite = IO::File->new("+<$filePath");

    if ( defined($fhRead) and defined($fhWrite) ) {
        my $bomHeader;
        $fhRead->sysread( $bomHeader, 3 );
        if ( $bomHeader eq "\xef\xbb\xbf" ) {

            $fhRead->seek( 3, 0 );
            $fhWrite->seek( 0, 0 );

            my $buf;
            my $len      = 0;
            my $totalLen = 0;

            do {
                $len = $fhRead->sysread( $buf, 16 );
                $fhWrite->syswrite( $buf, $len );
                $totalLen = $totalLen + $len;
            } while ( $len > 0 );

            $fhWrite->truncate($totalLen);
            print("INFO: Delete BOM header for file $filePath success.\n");
        }
        $fhRead->close();
        $fhWrite->close();
    }
    else {
        die("ERROR: Open file:$filePath failed $!");
    }
}

sub _getFileMd5Sum {
    my ( $self, $sqlPath ) = @_;
    my $md5Sum = `md5sum '$sqlPath'`;
    if ( $? == 0 ) {
        $md5Sum = substr( $md5Sum, 0, index( $md5Sum, ' ' ) );
    }
    else {
        die("ERROR: execute md5sum failed, $!.\n");
    }

    return $md5Sum;
}

sub needExecute {
    my ( $self, $sqlFile, $sqlFileStatus ) = @_;

    my $ret = 0;

    my $sqlFilePath = "$self->{sqlFileDir}/$sqlFile";

    my $md5Sum = $self->_getFileMd5Sum($sqlFilePath);

    if ( $self->{isForce} == 1 ) {
        $sqlFileStatus->updateStatus( md5 => $md5Sum );
        $ret = 1;
    }
    elsif ( $md5Sum eq $sqlFileStatus->getStatusValue('md5') ) {
        if ( $sqlFileStatus->getStatusValue('status') eq 'succeed' ) {
            print("INFO: Sql file:$sqlFile has been executed succeed, ignore.\n");
        }
        else {
            $ret = 1;
        }
    }
    else {
        $sqlFileStatus->updateStatus( md5 => $md5Sum );
        $ret = 1;
    }

    return $ret;
}

sub checkWaitInput {
    my ( $self, $sqlFile, $sqlFileStatus ) = @_;

    my $isWaitInput = 0;

    my $logFileDir   = $self->{logFileDir};
    my $pipePath     = "$logFileDir/$sqlFile.txt.run.pipe";
    my $pipeDescPath = "$logFileDir/$sqlFile.txt.run.pipe.json";

    if ( $sqlFileStatus->loadAndGetStatusValue('status') eq 'running' ) {
        if ( -e $pipePath and -e $pipeDescPath ) {
            $isWaitInput = 1;
            my $pipeDesc     = Utils::getFileContent($pipeDescPath);
            my $pipeDescJson = from_json($pipeDesc);
            $sqlFileStatus->updateStatus( interact => $pipeDescJson, status => 'waitInput' );
        }
    }
    elsif ( $sqlFileStatus->loadAndGetStatusValue('status') eq 'waitInput' ) {
        if ( not -e $pipePath ) {
            $sqlFileStatus->updateStatus( interact => undef, status => 'running' );
        }
    }

    return $isWaitInput;
}

sub execSqlFiles {
    my ($self) = @_;

    my $sqlFiles = $self->{sqlFiles};
    my $jobPath  = $self->{jobPath};

    my $hasError = 0;

    foreach my $sqlFile (@$sqlFiles) {
        my $sqlFileStatus = SQLFileStatus->new(
            $sqlFile,
            dbInfo    => $self->{dbInfo},
            jobPath   => $jobPath,
            phaseName => $self->{phaseName},
            istty     => $self->{istty}
        );
        my $checkRet = $self->needExecute( $sqlFile, $sqlFileStatus );

        if ( $checkRet == 1 ) {
            my $pid = fork();
            if ( $pid == 0 ) {
                my $rc = $self->execOneSqlFile( $sqlFile, $sqlFileStatus );
                exit($rc);
            }
            else {
                my $exitPid;
                my $isPreWaitInput = 0;
                my $isWaitInput    = 0;
                while ( ( $exitPid = waitpid( -1, 1 ) ) >= 0 ) {
                    if ( $exitPid eq 0 ) {
                        $isWaitInput = $self->checkWaitInput( $sqlFile, $sqlFileStatus );
                        if ( $isWaitInput == 1 and $isPreWaitInput != 1 ) {
                            AutoExecUtils::informNodeWaitInput( $self->{dbInfo}->{resourceId} );
                        }
                        $isPreWaitInput = $isWaitInput;

                        sleep(2);
                        next;
                    }

                    my $rc = $?;
                    $rc = $rc >> 8 if ( $rc > 255 );
                    if ( $rc ne 0 ) {
                        $hasError = 1;
                    }
                }
            }
        }

        if ( $hasError == 1 ) {
            last;
        }
    }

    return $hasError;
}

sub checkOneSqlFile {
    my ( $self, $sqlFile, $sqlFileStatus ) = @_;

    my $hasError = 0;

    my $sqlFilePath = "$self->{sqlFileDir}/$sqlFile";

    $self->_checkAndDelBom($sqlFilePath);

    my $md5Sum = $self->_getFileMd5Sum($sqlFilePath);

    if ( $sqlFileStatus->getStatusValue('md5') eq '' ) {
        $sqlFileStatus->updateStatus( md5 => $md5Sum, status => "pending", warnCount => 0, interact => undef, startTime => undef, endTime => undef );
    }
    elsif ( $md5Sum ne $sqlFileStatus->getStatusValue('md5') ) {
        $sqlFileStatus->updateStatus( md5 => $md5Sum, isModifed => 1, warnCount => 0, interact => undef, startTime => undef, endTime => undef );
    }
}

sub checkSqlFiles {
    my ($self) = @_;

    my $sqlFiles = $self->{sqlFiles};
    my $jobPath  = $self->{jobPath};

    my $hasError = 0;
    foreach my $sqlFile (@$sqlFiles) {
        my $sqlDir = dirname($sqlFile);

        if ( -e "$jobPath/file/$sqlFile" ) {
            my $sqlFileStatus = SQLFileStatus->new(
                $sqlFile,
                dbInfo    => $self->{dbInfo},
                jobPath   => $jobPath,
                phaseName => $self->{phaseName},
                istty     => $self->{istty}
            );

            if ( -e "$self->{sqlFileDir}/$sqlFile" ) {
                unlink("$self->{sqlFileDir}/$sqlFile");
            }
            if ( not -e "$self->{sqlFileDir}/$sqlDir" ) {
                mkpath("$self->{sqlFileDir}/$sqlDir");
            }

            if ( not link( "$jobPath/file/$sqlFile", "$self->{sqlFileDir}/$sqlFile" ) ) {
                $hasError = 1;
                print("ERROR: Copy $jobPath/file/$sqlFile to $self->{sqlFileDir}/$sqlFile failed $!\n");
            }

            $self->checkOneSqlFile( $sqlFile, $sqlFileStatus );
        }
        else {
            $hasError = 1;
            print("ERROR: Sql file '$jobPath/file/$sqlFile' not exists.\n");
        }
    }

    return $hasError;
}

1;

