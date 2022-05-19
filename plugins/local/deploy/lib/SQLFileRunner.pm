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
use Digest::MD5;

use DBInfo;
use AutoExecUtils;
use DeployUtils;

use SQLFileStatus;

sub new {
    my ( $type, %args ) = @_;

    my $self = {
        jobId        => $args{jobId},
        deployEnv    => $args{deployEnv},
        toolsDir     => $args{toolsDir},
        tmpDir       => $args{tmpDir},
        jobPath      => $args{jobPath},
        phaseName    => $args{phaseName},
        dbSchemasMap => $args{dbSchemasMap},
        dbInfo       => $args{dbInfo},
        nodeInfo     => $args{nodeInfo},
        sqlFileDir   => $args{sqlFileDir},
        sqlStatusDir => $args{sqlStatusDir},
        logFileDir   => $args{logFileDir},
        fileCharset  => $args{fileCharset},

        sqlFiles   => $args{sqlFiles},
        isForce    => $args{isForce},
        isDryRun   => $args{isDryRun},
        istty      => $args{istty},
        isInteract => $args{isInteract}
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

    $self->{usedSchemas}  = [];
    $self->{sqlFileInfos} = [];

    if ( defined( $args{autocommit} ) and defined( $self->{dbInfo} ) ) {
        $self->{dbInfo}->{autocommit} = $args{autocommit};
    }

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

    $self->_initDir();

    return $self;
}

sub _initDir {
    my ($self) = @_;

    my $hasError = 0;

    my $sqlFileDir = $self->{sqlFileDir};
    if ( defined($sqlFileDir) and not -e $sqlFileDir ) {
        mkpath($sqlFileDir);
        my $err = $!;
        if ( not -e $sqlFileDir ) {
            $hasError = 1;
            print("ERROR: Create dir '$sqlFileDir' failed $err\n");
        }
    }

    my $sqlStatusDir = $self->{sqlStatusDir};
    if ( $sqlStatusDir and not -e $sqlStatusDir ) {
        mkpath($sqlStatusDir);
        my $err = $!;
        if ( not -e $sqlStatusDir ) {
            $hasError = 1;
            print("ERROR: Create dir '$sqlStatusDir' failed $err\n");
        }
    }

    my $logFileDir = $self->{logFileDir};
    if ( defined($logFileDir) and not -e $logFileDir ) {
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
        my $dbSchema       = lc( $sqlDirSegments[0] );
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
            local $?;
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
            $line =~ s/\x0D//g;
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

        if ( $rc > 0 ) {
            $hasError = 1;
            if ( defined($sqlStatus) and $sqlStatus ne 'failed' ) {
                $sqlFileStatus->updateStatus( status => 'aborted' );
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

        select($toParent);
        open( STDERR, ">&STDOUT" );

        #open( STDOUT, '>&', $toParent );
        #open( STDERR, '>&', $toParent );
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
        print("# Status=$sqlFileStatus->{status}->{status}\n");
        print("# MD5=$sqlFileStatus->{status}->{md5}\n");
        print( "# $dbType/$dbName Begin\@" . strftime( "%Y/%m/%d %H:%M:%S", localtime() ) . "\n" );
        print("#***************************************\n\n");

        my $startTime = time();
        my $handler;
        my $spawn;

        if ( $self->{isDryRun} == 1 ) {
            print("INFO: Dry run sql $sqlFilePath.\n");
            $sqlFileStatus->updateStatus( interact => undef, status => 'running', startTime => time(), endTime => undef );
        }
        else {
            eval {
                print( "INFO: Try to use SQLRunner " . uc($dbType) . ".\n" );
                require $requireName;

                $handler = $handlerName->new(
                    $sqlFilePath,
                    sqlFileStatus => $sqlFileStatus,
                    toolsDir      => $self->{toolsDir},
                    tmpDir        => $self->{tmpDir},
                    dbInfo        => $dbInfo,
                    charSet       => $fileCharset,
                    logFilePath   => $logFilePath,
                    isInteract    => $self->{isInteract}
                );
            };
            if ($@) {
                $hasError = 1;
                print("ERROR: Load SQLRunner failed.\n");
                print("ERROR: $@\n");
                exit($hasError);
            }

            $spawn = $handler->{spawn};
            if ( defined($spawn) ) {
                $spawn->log_stdout(0);
                $spawn->log_file(
                    sub {
                        if ( $handler->{hasLogon} == 1 ) {
                            print($_);
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

        $spawn = $handler->{spawn};
        if ( $hasError == 0 ) {
            if ( defined($spawn) ) {
                if ( defined( $spawn->exitstatus() ) and $spawn->exitstatus() == 0 ) {
                    print("\nFINEST:execute sql:$sqlFile success.\n");
                }
                else {
                    print("\nERROR:execute sql:$sqlFile failed.\n");
                    $hasError = 1;
                }
            }
            else {
                print("\nFINEST:execute sql:$sqlFile success.\n");
            }
        }
        else {
            print("\nERROR:execute sql:$sqlFile failed.\n");
            $hasError = 1;
        }

        my $endStatus;
        if ( $hasError == 0 ) {
            my $preStatus = $sqlFileStatus->getStatusValue('status');
            if ( $preStatus eq 'waitInput' ) {
                $endStatus = 'ignored';
            }
            else {
                $endStatus = 'succeed';
            }

            $sqlFileStatus->updateStatus( status => $endStatus, warnCount => $handler->{warningCount}, endTime => time() );
        }
        else {
            $endStatus = 'failed';
            $sqlFileStatus->updateStatus( status => $endStatus, warnCount => $handler->{warningCount}, endTime => time() );
        }

        my $consumeTime = time() - $startTime;
        print("\n=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=\n");
        print( "= End\@" . strftime( "%Y/%m/%d %H:%M:%S", localtime() ) . "\n" );
        print("= Status=$endStatus\n");
        print("= Elapsed time: $consumeTime seconds.\n");
        print("=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=\n\n");

        #exit sql execute child process
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
    my ( $self, $filePath ) = @_;
    my $fileFH = new IO::File("<$filePath");

    my $md5Hash = '';
    if ( defined($fileFH) ) {
        $md5Hash = Digest::MD5->new->addfile(*$fileFH)->hexdigest();
        $fileFH->close();
    }
    else {
        die("ERROR: Get md5sum of file:$filePath failed, $!\n");
    }

    return $md5Hash;
}

sub _getSqlDbInfo {
    my ( $self, $sqlFile ) = @_;

    my $dbSchemasMap = $self->{dbSchemasMap};

    my $dbInfo;
    if ( defined($dbSchemasMap) ) {

        #如果有dbSchemasMap属性，代表是自动发布批量运行SQL，区别于基于单一DB运行SQL
        my @sqlDirSegments = split( '/', $sqlFile );
        my $dbSchema       = lc( $sqlDirSegments[0] );
        $dbInfo = $dbSchemasMap->{$dbSchema};
    }
    else {
        #否则就是针对单一DB目标执行SQL文件，只有单库脚本
        $dbInfo = $self->{dbInfo};
    }

    return $dbInfo;
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

#Deprecated
sub checkWaitInput {
    my ( $self, $sqlFile, $sqlFileStatus ) = @_;

    #Deprecated
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
            saveToServer => 1,
            jobId        => $self->{jobId},
            deployEnv    => $self->{deployEnv},
            dbInfo       => $self->_getSqlDbInfo($sqlFile),
            sqlStatusDir => $self->{sqlStatusDir},
            sqlFileDir   => $self->{sqlFileDir}
        );
        my $checkRet = $self->needExecute( $sqlFile, $sqlFileStatus );

        if ( $checkRet == 1 ) {
            print("INFO: Execute sql file:$sqlFile...\n");
            my $rc        = $self->execOneSqlFile( $sqlFile, $sqlFileStatus );
            my $sqlStatus = $sqlFileStatus->loadAndGetStatusValue('status');
            print("ERROR: Execute $sqlFile return status:$sqlStatus.\n");
            $hasError = $hasError + $rc;
        }

        if ( $hasError != 0 ) {
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
            my $dbInfo        = $self->_getSqlDbInfo($sqlFile);
            my $sqlFileStatus = SQLFileStatus->new(
                $sqlFile,
                saveToServer => 1,
                jobId        => $self->{jobId},
                deployEnv    => $self->{deployEnv},
                dbInfo       => $dbInfo,
                sqlStatusDir => $self->{sqlStatusDir},
                sqlFileDir   => $self->{sqlFileDir}
            );
            my $checkRet = $self->needExecute( $sqlFile, $sqlFileStatus );

            if ( $checkRet == 1 ) {
                print("INFO: Execute sql file:$sqlFile...\n");
                my $pid = fork();
                if ( $pid == 0 ) {
                    $self->{logFileDir} = $self->{logFileDir} . "/$dbInfo->{host}-$dbInfo->{port}-$dbInfo->{resourceId}";
                    my $rc = $self->execOneSqlFile( $sqlFile, $sqlFileStatus );
                    exit $rc;
                }
                elsif ( $pid > 0 ) {
                    $runnerPidsMap->{$pid} = [ $sqlFile, $sqlFileStatus ];
                }
                else {
                    print("ERROR: Can not fork process to execute sql file:$sqlFile\n");
                    $hasError = $hasError + 1;
                }
            }
        }

        my $pid = 0;
        while ( ( $pid = waitpid( -1, 0 ) ) > 0 ) {
            my $rc = $?;
            if ( $rc > 255 ) {
                $rc = $rc >> 8;
            }

            my $sqlInfoArray  = $runnerPidsMap->{$pid};
            my $sqlFile       = $$sqlInfoArray[0];
            my $sqlFileStatus = $$sqlInfoArray[1];
            my $sqlStatus     = $sqlFileStatus->loadAndGetStatusValue('status');
            delete( $runnerPidsMap->{$pid} );
            if ( $rc ne 0 ) {
                $hasError = $hasError + 1;
                print("ERROR: Execute $sqlFile return status:$sqlStatus.\n");
            }
            else {
                print("INFO: Execute $sqlFile return status:$sqlStatus.\n");
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
        jobId          => $self->{jobId},
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

    #检查SQL是否需要运行，是否存在不正确的语法等
    #同时生成schema的信息，完成对shema连通性的检测
    my ($self) = @_;

    my $jobPath      = $self->{jobPath};
    my $sqlFiles     = $self->{sqlFiles};
    my $sqlFileDir   = $self->{sqlFileDir};
    my $dbSchemasMap = $self->{dbSchemasMap};
    my $sqlFileInfos = $self->{sqlFileInfos};
    my $hasError     = 0;

    my $usedSchemas = $self->{usedSchemas};
    foreach my $sqlFile (@$sqlFiles) {

        my $nodeInfo;
        if ( defined($dbSchemasMap) ) {

            #如果有dbSchemasMap属性，代表是自动发布批量运行SQL，区别于基于单一DB运行SQL
            my @sqlDirSegments = split( '/', $sqlFile );
            my $dbSchema       = lc( $sqlDirSegments[0] );
            push( @$usedSchemas, $dbSchema );
            my $dbInfo = $dbSchemasMap->{$dbSchema};
            $nodeInfo = $dbInfo->{node};
        }
        else {
            $nodeInfo = $self->{nodeInfo};
            if ( -e "$sqlFileDir/$sqlFile" ) {
                unlink("$sqlFileDir/$sqlFile");
            }

            if ( not link( "$jobPath/file/$sqlFile", "$sqlFileDir/$sqlFile" ) ) {
                $hasError = 1;
                print("ERROR: Copy $jobPath/file/$sqlFile to $sqlFileDir/$sqlFile failed $!\n");
            }
        }

        if ( -e "$sqlFileDir/$sqlFile" ) {
            my $sqlFileStatus = SQLFileStatus->new(
                $sqlFile,
                saveToServer => 0,
                jobId        => $self->{jobId},
                deployEnv    => $self->{deployEnv},
                dbInfo       => $self->_getSqlDbInfo($sqlFile),
                sqlStatusDir => $self->{sqlStatusDir},
                sqlFileDir   => $sqlFileDir
            );

            my $sqlInfo = $self->checkOneSqlFile( $sqlFile, $nodeInfo, $sqlFileStatus );
            push( @$sqlFileInfos, $sqlInfo );
            print("INFO: Sql file:$sqlFile checked.\n");
        }
        else {
            $hasError = $hasError + 1;
            print("ERROR: Sql file '$sqlFileDir/$sqlFile' not exists.\n");
        }
    }

    return $hasError;
}

sub restoreSqlStatuses {
    my ( $self, $sqlInfoList ) = @_;

    my $sqlFileDir = $self->{sqlFileDir};
    foreach my $sqlInfo (@$sqlInfoList) {
        my $sqlFile       = $sqlInfo->{sqlFile};
        my $status        = $sqlInfo->{status};
        my $md5           = $sqlInfo->{md5};
        my $sqlFileStatus = SQLFileStatus->new(
            $sqlFile,
            saveToServer => 0,
            jobId        => $self->{jobId},
            deployEnv    => $self->{deployEnv},
            sqlStatusDir => $self->{sqlStatusDir}
        );

        $sqlFileStatus->_setStatus( status => $status, md5 => $md5 );
    }
}

sub checkDBSchemas {
    my ($self) = @_;

    my $hasError     = 0;
    my $dbSchemasMap = $self->{dbSchemasMap};
    my $usedSchemas  = $self->{usedSchemas};

    foreach my $dbSchema (@$usedSchemas) {
        my $dbInfo = $dbSchemasMap->{$dbSchema};
        my $dbType = uc( $dbInfo->{dbType} );
        my $dbName = $dbInfo->{dbName};

        my $handlerName = uc($dbType) . 'SQLRunner';
        my $requireName = $handlerName . '.pm';

        my $handler;
        eval {
            print( "INFO: Try to use SQLRunner " . uc($dbType) . " to test.\n" );
            require $requireName;

            $handler = $handlerName->new(
                'test.sql',
                toolsDir => $self->{toolsDir},
                tmpDir   => $self->{tmpDir},
                dbInfo   => $dbInfo,
                charSet  => 'UTF-8'
            );
            my $hasLogon = $handler->test();
            if ( $hasLogon != 1 ) {
                $hasError = $hasError + 1;
            }
        };
        if ($@) {
            $hasError = $hasError + 1;
            print("ERROR: $@");
        }
    }

    return $hasError;
}

sub testByIpPort {
    my ( $self, $dbType, $host, $port, $dbName, $user, $pass ) = @_;

    my $node = {
        nodeType => $dbType,
        nodeName => $dbName,
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
        $handler = $handlerName->new(
            'test.sql',
            toolsDir => $self->{toolsDir},
            tmpDir   => $self->{tmpDir},
            dbInfo   => $dbInfo,
            charSet  => 'UTF-8'
        );
        $hasLogon = $handler->test();
    };
    if ($@) {
        print("ERROR: $@");
    }

    return $hasLogon;
}

1;

