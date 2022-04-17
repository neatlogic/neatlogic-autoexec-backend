#!/usr/bin/perl
use strict;

package SQLFileRunner;

use FindBin;
use Encode;
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
use DeployUtils;

use SQLFileStatus;

sub new {
    my ( $type, %args ) = @_;

    my $self = {
        jobPath      => $args{jobPath},
        phaseName    => $args{phaseName},
        dbSchemasMap => $args{dbSchemasMap},
        dbInfo       => $args{dbInfo},
        nodeInfo     => $args{nodeInfo},
        sqlFileDir   => $args{sqlFileDir},
        sqlStatusDir => $args{sqlStatusDir},

        fileCharset => $args{fileCharset},

        sqlFiles => $args{sqlFiles},
        istty    => $args{istty},
        isForce  => $args{isForce},
        isDryRun => $args{isDryRun}
    };

    #$dbInfo包含节点信息以外，还包含以下DB的扩展属性
    # dbNode      => $args{dbNode},
    # dbVersion    => $args{dbVersion},
    # dbArgs       => $args{dbArgs},
    # oraWallet    => $args{oraWallet},
    # locale       => $args{locale},
    # autocommit   => $args{autocommit},
    # ignoreErrors => $args{ignoreErrors}
    bless( $self, $type );

    $self->{sqlFileInfos} = [];

    my $jobPath = $args{jobPath};
    if ( not defined($jobPath) or $jobPath eq '' ) {
        $jobPath = getcwd();
    }
    $self->{jobPath} = $jobPath;

    my $phaseName = $args{phaseName};
    if ( not defined($phaseName) or $phaseName eq '' ) {
        $phaseName = 'sql-file';
    }
    $self->{phaseName} = $phaseName;

    $self->_initDir( \%args );

    return $self;
}

sub _initDir {
    my ( $self, %args ) = @_;

    my $hasError = 0;

    my $sqlFileDir = $self->{sqlFileDir};
    if ( not -e $sqlFileDir ) {
        mkpath($sqlFileDir);
        my $err = $!;
        if ( not -e $sqlFileDir ) {
            $hasError = 1;
            print("ERROR: Create dir '$sqlFileDir' failed $err\n");
        }
    }

    my $sqlStatusDir = $self->{sqlStatusDir};
    if ($sqlStatusDir) {
        mkpath($sqlStatusDir);
        my $err = $!;
        if ( not -e $sqlStatusDir ) {
            $hasError = 1;
            print("ERROR: Create dir '$sqlStatusDir' failed $err\n");
        }
    }

    my $logFileDir = $self->{logFileDir};
    if ( not -e $logFileDir ) {
        mkpath($logFileDir);
        my $err = $!;
        if ( not -e $logFileDir ) {
            $hasError = 1;
            print("ERROR: Create dir '$logFileDir' failed $err\n");
        }
    }

    if ( $hasError == 1 ) {
        exit(2);
    }

    return;
}

sub execOneSqlFile {
    my ( $self, $sqlFile, $sqlFileStatus ) = @_;

    my $dbInfo;
    my $dbSchemasMap = $self->{dbSchemasMap};
    if ( defined($dbSchemasMap) ) {

        #如果有dbSchemasMap属性，代表是自动发布批量运行SQL，区别于基于单一DB运行SQL
        my @sqlDirSegments = split( '/', $sqlFile );
        my $dbSchema = lc( $sqlDirSegments[0] );
        $dbInfo = $dbSchemasMap->{$dbSchema};
    }
    else {
        #否则就是针对单一DB目标执行SQL文件，只有单库脚本
        $dbInfo = $self->{dbInfo};
    }

    my $hasError = 0;

    my $logFileDir = $self->{logFileDir};
    my $sqlDir     = dirname($sqlFile);
    if ( not -e "$logFileDir/$sqlDir" ) {
        mkpath("$logFileDir/$sqlDir");
    }

    my $logFileDir = $self->{logFileDir};
    if ( not -e $logFileDir ) {
        if ( not mkdir($logFileDir) ) {
            $hasError = 1;
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

    if ( -e $logFilePath ) {
        if ( not unlink($logFilePath) ) {
            $hasError = 1;
            print("ERROR: Switch log file $logFilePath failed, $!\n");
        }
    }

    my $logFH = IO::File->new(">$logFilePath");
    $logFH->autoflush(1);
    if ( not link( $logFilePath, $hisLogFilePath ) ) {
        $hasError = 1;
        print("ERROR: Create log file path failed, $!\n");
    }

    my $sqlFilePath = "$self->{sqlFileDir}/$sqlFile";
    my $fileCharset = $self->{fileCharset};
    if ( not defined($fileCharset) ) {
        $fileCharset = DeployUtils->guessEncoding($sqlFilePath);
        if ( defined($fileCharset) ) {
            print("INFO: Detech charset $fileCharset.\n");
        }
        else {
            print("ERROR: Can not detect $sqlFilePath charset.\n");
            $hasError = 1;
        }
    }
    else {
        print("INFO: Use charset: $fileCharset\n");
    }

    if ( $hasError == 1 ) {
        return $hasError;
    }

    pipe( my $fromParent, my $toChild );
    pipe( my $fromChild,  my $toParent );
    $toParent->binmode();
    $toParent->autoflush(1);

    my $pid = fork();
    if ( $pid > 0 ) {
        close($fromParent);
        close($toParent);
        close($toChild);

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

        my $timeStr;
        my @nowTime;
        while ( my $line = <$fromChild> ) {
            @nowTime = localtime();
            $timeStr = sprintf( "%02d:%02d:%02d", $nowTime[2], $nowTime[1], $nowTime[0] );
            if ( $fileCharset ne 'UTF-8' ) {
                $line = Encode::encode( 'utf-8', Encode::decode( $fileCharset, $line ) );
            }
            if ( not $self->{istty} ) {
                print $logFH ( $timeStr, ' ', $line );
            }
            else {
                print( $timeStr, ' ', $line );
            }
        }

        close($fromChild);
        waitpid( $pid, 0 );
        my $rc = $?;

        my $sqlStatus = $sqlFileStatus->loadAndGetStatusValue('status');

        if ( $rc > 255 ) {
            $hasError = 1;
            $rc       = $rc >> 8;
        }
        elsif ( $rc > 0 ) {
            $hasError = 1;
            if ( defined($sqlStatus) and $sqlStatus ne 'failed' ) {
                $sqlFileStatus->updateStatus( status => 'aborted', warnCount => $ENV{WARNING_COUNT}, endTime => time() );
            }
        }
        else {
            if ( defined($sqlStatus) and ( $sqlStatus eq 'failed' or $sqlStatus eq 'aborted' ) ) {
                $hasError = 1;
            }
        }

        return $hasError;
    }
    else {
        if ( not defined($pid) ) {
            print("ERROR: Cannot fork process to execute sqlfile: $!");
        }
        close($toChild);
        close($fromChild);
        close($fromParent);
        open( STDOUT, '>&', $toParent );
        open( STDERR, '>&', $toParent );
        binmode( STDOUT, 'encoding(UTF-8)' );
        binmode( STDERR, 'encoding(UTF-8)' );

        DeployUtils->sigHandler(
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

        my $dbType = uc( $dbInfo->{dbType} );
        my $dbName = $dbInfo->{dbName};

        my $handlerName = uc($dbType) . 'SQLRunner';
        my $requireName = $handlerName . '.pm';

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

                $handler = $handlerName->new( $dbInfo, $sqlFilePath, $fileCharset, $logFilePath );
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

        exit($hasError);
    }
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
            my $pipeDesc     = DeployUtils->getFileContent($pipeDescPath);
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

    my $hasError = 0;

    foreach my $sqlFile (@$sqlFiles) {

        my $sqlFileStatus = SQLFileStatus->new(
            $sqlFile,
            sqlStatusDir => $self->{sqlStatusDir},
            sqlFileDir   => $self->{sqlFileDir},
            istty        => $self->{istty}
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
                            AutoExecUtils::informNodeWaitInput( $self->{dbNode}->{nodeId} );
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

sub execSqlFileSets {
    my ( $self, $sqlFileSets ) = @_;

    my $hasError = 0;

    foreach my $sqlFiles (@$sqlFileSets) {
        my $runnerPidsMap = {};
        foreach my $sqlFile (@$sqlFiles) {
            my $sqlFileStatus = SQLFileStatus->new(
                $sqlFile,
                sqlStatusDir => $self->{sqlStatusDir},
                sqlFileDir   => $self->{sqlFileDir},
                istty        => $self->{istty}
            );
            my $checkRet = $self->needExecute( $sqlFile, $sqlFileStatus );

            if ( $checkRet == 1 ) {
                my $pid = fork();
                if ( $pid == 0 ) {
                    my $rc = $self->execOneSqlFile( $sqlFile, $sqlFileStatus );
                    $hasError = $hasError + $rc;
                }
                else {
                    $runnerPidsMap->{$pid} = [ $sqlFile, $sqlFileStatus ];
                }
            }
        }

        foreach my $pid ( keys(%$runnerPidsMap) ) {
            my $exitPid;
            my $isPreWaitInput = 0;
            my $isWaitInput    = 0;
            if ( ( $exitPid = waitpid( $pid, 1 ) ) >= 0 ) {
                if ( $exitPid eq 0 ) {
                    my $sqlInfo       = $runnerPidsMap->{$pid};
                    my $sqlFile       = $$sqlInfo[0];
                    my $sqlFileStatus = $$sqlInfo[1];
                    $isWaitInput = $self->checkWaitInput( $sqlFile, $sqlFileStatus );
                    if ( $isWaitInput == 1 and $isPreWaitInput != 1 ) {
                        AutoExecUtils::informNodeWaitInput( $self->{dbNode}->{nodeId} );
                    }
                    $isPreWaitInput = $isWaitInput;

                    sleep(2);
                    next;
                }

                my $rc = $?;
                $rc = $rc >> 8 if ( $rc > 255 );
                if ( $rc ne 0 ) {
                    $hasError = $hasError + 1;
                }
                delete( $runnerPidsMap->{$pid} );
            }
        }

        if ( $hasError != 0 ) {
            last;
        }
    }

    return $hasError;
}

sub checkOneSqlFile {
    my ( $self, $sqlFile, $nodeInfo, $sqlFileStatus ) = @_;

    # my $dbInfo;
    # my $dbSchemasMap = $self->{dbSchemasMap};
    # if ( defined($dbSchemasMap) ) {
    #     my $dbSchema = lc( dirname($sqlFile) );
    #     $dbInfo = $dbSchemasMap->{$dbSchema};
    # }
    # else {
    #     $dbInfo = $self->{dbInfo};
    # }

    my $hasError = 0;

    my $sqlFilePath = "$self->{sqlFileDir}/$sqlFile";

    $self->_checkAndDelBom($sqlFilePath);

    my $preStatus;
    my $md5Sum = $self->_getFileMd5Sum($sqlFilePath);
    if ( $sqlFileStatus->getStatusValue('md5') eq '' ) {
        $preStatus = $sqlFileStatus->updateStatus( md5 => $md5Sum, status => "pending", warnCount => 0, interact => undef, startTime => undef, endTime => undef );
    }
    elsif ( $md5Sum ne $sqlFileStatus->getStatusValue('md5') ) {
        $preStatus = $sqlFileStatus->updateStatus( md5 => $md5Sum, isModifed => 1, warnCount => 0, interact => undef, startTime => undef, endTime => undef );
    }

    if ( not defined($preStatus) or $preStatus eq '' ) {
        $preStatus = 'pending';
    }

    my $sqlInfo = {
        resourceId     => $nodeInfo->{resourceId},
        nodeName       => $nodeInfo->{nodeName},
        host           => $nodeInfo->{host},
        port           => $nodeInfo->{port},
        accessEndpoint => $nodeInfo->{accessEndpoint},
        sqlFile        => $sqlFile,
        status         => $preStatus,
        md5            => $md5Sum
    };

    return $sqlInfo;
}

sub checkSqlFiles {
    my ($self) = @_;

    my $sqlFiles     = $self->{sqlFiles};
    my $sqlFileDir   = $self->{sqlFileDir};
    my $dbSchemasMap = $self->{dbSchemasMap};
    my $sqlFileInfos = $self->{sqlFileInfos};
    my $hasError     = 0;

    my @usedSchemas = ();
    foreach my $sqlFile (@$sqlFiles) {

        if ( -e "$sqlFileDir/$sqlFile" ) {
            my $nodeInfo;
            if ( defined($dbSchemasMap) ) {

                #如果有dbSchemasMap属性，代表是自动发布批量运行SQL，区别于基于单一DB运行SQL
                my @sqlDirSegments = split( '/', $sqlFile );
                my $dbSchema = lc( $sqlDirSegments[0] );
                push( @usedSchemas, $dbSchema );
                my $dbInfo   = $dbSchemasMap->{$dbSchema};
                my $nodeInfo = $dbInfo->{node};
            }
            else {
                $nodeInfo = $self->{nodeInfo};
            }

            my $sqlFileStatus = SQLFileStatus->new(
                $sqlFile,
                sqlStatusDir => $self->{sqlStatusDir},
                sqlFileDir   => $sqlFileDir,
                istty        => $self->{istty}
            );

            my $sqlInfo = $self->checkOneSqlFile( $sqlFile, $nodeInfo, $sqlFileStatus );
            push( @$sqlFileInfos, $sqlInfo );
        }
        else {
            $hasError = $hasError + 1;
            print("ERROR: Sql file '$sqlFileDir/$sqlFile' not exists.\n");
        }
    }

    foreach my $dbSchema (@usedSchemas) {
        my $dbInfo = $dbSchemasMap->{$dbSchema};
        my $dbType = uc( $dbInfo->{dbType} );
        my $dbName = $dbInfo->{dbName};

        my $handlerName = uc($dbType) . 'SQLRunner';
        my $requireName = $handlerName . '.pm';

        my $handler;
        eval {
            print( "INFO: Try to use SQLRunner " . uc($dbType) . " to test.\n" );
            require $requireName;

            $handler = $handlerName->new( $dbInfo, 'test.sql', 'UTF-8' );
            my $hasLogon = $handler->test();
            if ( $hasLogon != 1 ) {
                $hasError = $hasError + 1;
            }
        };
        if ($@) {
            $hasError = $hasError + 1;
            print("ERROR: $@\n");
        }

    }

    return $hasError;
}

sub testByIpPort {
    my ( $self, $dbType, $host, $port, $dbName, $user, $pass ) = @_;

    my $node = {
        nodeType => $dbType,
        host     => $host,
        port     => $port,
        username => $user,
        password => $pass
    };
    my $args = {
        autocommit => 1,
        dbArgs     => ''
    };

    my $dbInfo = DBInfo->new( $node, $args );

    if ( not defined($dbType) and not defined($dbName) ) {
        print("ERROR: can not find db type and db name, check the db configuration.\n");
        exit(-1);
    }

    my $handlerName = uc($dbType) . 'SQLRunner';
    my $requireName = $handlerName . '.pm';

    my $hasLogon = 0;
    my $handler;
    eval {
        require $requireName;
        $handler = $handlerName->new( $dbInfo, 'test.sql', 'UTF-8' );
        $hasLogon = $handler->test();
    };
    if ($@) {
        print("ERROR: $@\n");
    }

    return $hasLogon;
}

1;

