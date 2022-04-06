#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

package SQLRunBatch;

use strict;
use POSIX qw(WNOHANG);
use IO::File;
use File::Path;
use RunBatch;
use RunStatus;

#use RUNLock;
use Utils;
use ServerAdapter;
use SQLRunner;
use SQLRunStatus;

sub new {
    my ( $pkg, $envPath, $version ) = @_;

    $pkg = ref($pkg) || $pkg;
    unless ($pkg) {
        $pkg = "SQLRunBatch";
    }
    my $self = {};
    bless( $self, $pkg );

    $SIG{'USR2'} = sub {
        $ENV{RUN_WITH_DBA} = 1;
        kill( 'USR2', getppid() );
    };

    $self->{shareStatus} = 0;
    $self->{isForce}     = 0;
    return $self;
}

sub sqlexecOne {
    my ( $self, $scope, $envInfo, $bookPath, $bookItem, $ticket, $oneSqlFile, $logPath, $md5Hash, $isVerbose ) = @_;
    my $exitCode = 0;
    $ENV{SQL} = $oneSqlFile;

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
    my $timeSpan = sprintf( "%04d%02d%02d-%02d%02d%02d-%d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec, $$ );
    $ENV{RUN_TIMESPAN} = $timeSpan;

    my $logRelPath = "db/$oneSqlFile.$bookItem.$ticket.$timeSpan.log";
    ServerAdapter::callback( 'running', $scope, $ticket, $bookItem, $logRelPath, $envInfo->{sys}, $envInfo->{subsys}, $envInfo->{version}, $envInfo->{env}, '', $oneSqlFile );

    print("INFO: begin execute $bookItem $oneSqlFile ===============\n");

    #取消此调用方法，使用管道的方式，便于进行统一处理
    #my $ret = Utils::execmd("bash $bookPath");

    #初始化sql运行日志和symbolic link
    my $pos = rindex( $oneSqlFile, '/' );
    my $fPath = substr( $oneSqlFile, 0, $pos );
    my $fName = substr( $oneSqlFile, $pos + 1 );
    my $logPrefix   = "$fName.$bookItem.$ticket";
    my $logName     = "$logPrefix.$timeSpan.log";
    my $logFilePath = "$logPath/$logRelPath";

    mkpath("$logPath/db/$fPath");
    my $logFH = IO::File->new(">>$logFilePath");
    if ( not defined($logFH) ) {
        die("ERROR: Can not create log file:$logFilePath, $!");
    }
    $logFH->autoflush(1);

    my $logLinkPath = "$logPath/db/$fPath/$logPrefix.log";
    my $linkToPath;
    if ( -l $logLinkPath or -e $logLinkPath ) {
        $linkToPath = readlink($logLinkPath);
    }
    if ( $logName ne $linkToPath ) {
        unlink($logLinkPath);
        symlink( $logName, $logLinkPath );
    }
    $ENV{RUN_PRELOGNAME} = $linkToPath;

    #日志初始化完成

    my $PROGHDLE;

    my $pid = open( $PROGHDLE, "setsid bash $bookPath 2>\&1 |" );

    my $timeStr;
    my @nowTime;
    while (<$PROGHDLE>) {
        @nowTime = localtime();
        $timeStr = sprintf( "%02d:%02d:%02d", $nowTime[2], $nowTime[1], $nowTime[0] );

        #日志前部加上时间，会影响ezproxy获取日志染色，先不打开, by wenhb
        print $logFH ( $timeStr, ' ', $_ );
    }
    close($PROGHDLE);
    my $ret = $?;
    $logFH->close();

    my $statusPath = $self->{statusRootPath} . "/$oneSqlFile.status";
    my ( $status, $warnCount, $error ) = SQLRunStatus::getStatusAndWarnCount($statusPath);
    $ENV{WARNING_COUNT} = $warnCount;
    $ENV{HAS_ERROR}     = $error;

    if ( $ret ne 0 ) {
        my $failStatus = 'failed';
        if ( $ret < 256 and defined($status) and $status ne 'failed' ) {
            $failStatus = 'aborted';
        }

        #print("ERROR: Batch run all deploy phase $failStatus at execute $oneSqlFile.\n");
        $exitCode = $ret;
        ServerAdapter::callback( $failStatus, $scope, $ticket, $bookItem, $logRelPath, $envInfo->{sys}, $envInfo->{subsys}, $envInfo->{version}, $envInfo->{env}, '', $oneSqlFile, undef, $md5Hash );
    }
    else {
        if ( defined($status) and $status ne "" ) {
            my $sqlStatus = 'succeed';
            if ( defined($status) and ( $status eq 'failed' or $status eq 'aborted' ) ) {
                $sqlStatus = $status;
            }

            ServerAdapter::callback( $sqlStatus, $scope, $ticket, $bookItem, $logRelPath, $envInfo->{sys}, $envInfo->{subsys}, $envInfo->{version}, $envInfo->{env}, '', $oneSqlFile, undef, $md5Hash );
        }
    }

    return $exitCode;
}

sub isSqlWaitInput {
    my ( $self, $allSqlFiles, $logPath, $ticketId, $bookItem ) = @_;

    my $isWaitInput = 0;

    my $oneSqlFile;
    foreach $oneSqlFile (@$allSqlFiles) {
        my $pipePath = "$logPath/db/$oneSqlFile.$bookItem.$ticketId.run.pipe";
        if ( -e $pipePath ) {
            $isWaitInput = 1;
            last;
        }
    }

    return $isWaitInput;
}

sub sqlexecStatus {
    my ( $self, $scope, $allSqlFiles, $statusRootPath, $logPath, $ticketId, $bookItem ) = @_;

    my $allStatus         = "pending";
    my $globalWaitInput   = 0;
    my $globalLastRunTime = 0;
    my $totalCount        = scalar(@$allSqlFiles);
    my $runCount          = 0;
    my $abortCount        = 0;
    my $failCount         = 0;
    my $sucCount          = 0;
    my $pendingCount      = 0;
    my $waitInputCount    = 0;
    my $warningCount      = 0;
    my $hasError          = 0;

    my $oneSqlFile;
    foreach $oneSqlFile (@$allSqlFiles) {
        my $pipePath = "$logPath/db/$oneSqlFile.$bookItem.$ticketId.run.pipe";

        if ( -e $pipePath ) {
            $globalWaitInput = 1;
            last;
        }

        my $statusPath = "$statusRootPath/$oneSqlFile.status";
        my ( $status, $warnCount, $error ) = SQLRunStatus::getStatusAndWarnCount($statusPath);
        $warningCount = $warningCount + $warnCount;
        if ( $error > 0 ) {
            $hasError = 1;
        }

        if ( $status eq 'running' ) {
            $runCount++;
            if ( -e $pipePath ) {
                $waitInputCount++;
            }
        }
        elsif ( $status eq 'failed' ) {
            $failCount++;
        }
        elsif ( $status eq 'succeed' ) {
            $sucCount++;
        }
        elsif ( $status eq 'aborted' ) {
            $abortCount++;
        }
        elsif ( $status eq 'pending' ) {
            $pendingCount++;
        }
    }

    if ( $sucCount eq $totalCount ) {
        $allStatus = 'succeed';
    }
    elsif ( $waitInputCount > 0 ) {
        $allStatus = 'waitinput';
    }
    elsif ( $runCount > 0 ) {
        $allStatus = 'running';
    }
    elsif ( $failCount > 0 ) {
        $allStatus = 'failed';
    }
    elsif ( $abortCount > 0 ) {
        $allStatus = 'aborted';
    }
    elsif ( $pendingCount > 0 or $sucCount > 0 ) {
        $allStatus = 'pending';
    }
    else {
        $allStatus = 'none';
    }

    $ENV{WARNING_COUNT} = $warningCount;
    $ENV{HAS_ERROR}     = $hasError;

    return $allStatus;
}

sub sqlexec {
    my ( $self, $scope, $runBatch, $envInfo, $bookPath, $bookItem, $ticket, $allSqlFiles, $logPath, $parallelCount, $isVerbose ) = @_;
    my $statusPath = $envInfo->{distressrc} . "/db.status";

    #my $sqlexecLock = RUNLock->new("$statusPath/sqlexec.lock");
    #$sqlexecLock->lock();

    my $exitCode = 0;

    my $parCount = 0;
    my ( $prefix, @runSqlSet, @runSqlSets );
    my $oneSqlFile;
    foreach $oneSqlFile (@$allSqlFiles) {
        my $sqlStatusFile    = $envInfo->{dbstatuslog} . "/$oneSqlFile.status";
        my $sqlEnvStatusFile = $envInfo->{envdbstatuslog} . "/$oneSqlFile.status";

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
    push( @runSqlSets, \@runSqlSet ) if ( scalar(@runSqlSet) > 0 );

    foreach my $runSet (@runSqlSets) {

        my $oneSqlFile;
        foreach $oneSqlFile (@$runSet) {
            my $sqlRunner = SQLRunner->new( statusDirPrefix => $self->{statusRootPath} );

            #my $md5Hash         = SQLRunner::getFileMd5( $envInfo->{distressrc} . "/db/$oneSqlFile" );
            my $md5Hash   = $sqlRunner->getFileMd5( $envInfo->{distressrc} . "/db/$oneSqlFile" );
            my $needToRun = 1;
            if ( $self->{isForce} == 0 and exists $ENV{IS_JOB} ) {

                #$needToRun = SQLRunner::isNeedToRun( $oneSqlFile, $md5Hash, $statusDirPrefix );
                $needToRun = $sqlRunner->isNeedToRun( $oneSqlFile, $md5Hash );
            }
            if ( $needToRun > 0 ) {
                my $pid = fork();
                if ( $pid == 0 ) {
                    $ENV{SQL} = $oneSqlFile;
                    ServerAdapter::callback( 'running', $scope, $ticket, $bookItem, '', $envInfo->{sys}, $envInfo->{subsys}, $envInfo->{version}, $envInfo->{env} );

                    my $rc = $self->sqlexecOne( $scope, $envInfo, $bookPath, $bookItem, $ticket, $oneSqlFile, $logPath, $md5Hash, $isVerbose );

                    $rc = $rc >> 8 if ( $rc > 255 );
                    exit($rc);
                }
            }
        }

        my $exitPid;
        my $isPreWaitInput = 0;
        while ( ( $exitPid = waitpid( -1, WNOHANG ) ) >= 0 ) {
            if ( $exitPid eq 0 ) {
                my $isWaitInput = $self->isSqlWaitInput( $allSqlFiles, $logPath, $ticket, $bookItem );
                if ( $isWaitInput == 1 and $isPreWaitInput == 0 ) {

                    #my $jobId = $ENV{JOB_ID};
                    #$runBatch->notice( $envInfo, $envInfo->{version}, $bookItem, 2, $ticket, $jobId );
                    ServerAdapter::callback( 'waitinput', $scope, $ticket, $bookItem, '', $envInfo->{sys}, $envInfo->{subsys}, $envInfo->{version}, $envInfo->{env} );
                }
                $isPreWaitInput = $isWaitInput;

                sleep(2);
                next;
            }

            my $rc = $?;
            $rc = $rc >> 8 if ( $rc > 255 );
            if ( $rc ne 0 and $exitCode eq 0 ) {
                $exitCode = $rc;
            }
        }

        last if ( $exitCode ne 0 );
    }

    #$sqlexecLock->release();
    return $exitCode;
}

sub parseSqlPluginOpts {
    my ( $self, $bookPath ) = @_;

    my $filter;
    my $index;
    my $fh = IO::File->new("<$bookPath");
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;
            if ( $line eq '' or index( $line, '#' ) eq 0 ) {
                next;
            }

            if ( $line !~ /^\s*dbexec\s/ ) {
                next;
            }

            #if ( $line =~ /\s--?sharestatus\s|\s--?sharestatus$/ ) {
            #    $self->{shareStatus} = 1;
            #    $ENV{SQL_SHARE_STATUS} = 1;
            #}
            #else {
            #    $ENV{SQL_SHARE_STATUS} = 0;
            #}

            if ( $line =~ /\s--?filter\s+(.*)$/ ) {
                my $optVal = $1;
                if ( $optVal =~ /^"([^"]+)"/ ) {
                    $filter = $1;
                }
                elsif ( $optVal =~ /^'([^']+)'/ ) {
                    $filter = $1;
                }
                elsif ( $optVal !~ /^[-'"]/ and $optVal =~ /([^\s]+)/ ) {
                    $filter = $1;
                }

                $self->{filter} = $filter;
            }

            if ( $line =~ /\s--?index\s+(.*)$/ ) {
                my $optVal = $1;
                if ( $optVal =~ /^"([^"]+)"/ ) {
                    $index = $1;
                }
                elsif ( $optVal =~ /^'([^']+)'/ ) {
                    $index = $1;
                }
                elsif ( $optVal !~ /^[-'"]/ and $optVal =~ /([^\s]+)/ ) {
                    $index = $1;
                }
                $self->{index} = $index;
            }

            if ( $line =~ /\s--?force\s+(.*)$/ ) {
                $self->{isForce} = 1;
            }
        }
    }
}

sub checkIfRollback {
    my ( $self, $bookPath ) = @_;

    my $isRollback;

    my $filter;
    my $fh = IO::File->new("<$bookPath");
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;
            if ( $line eq '' or index( $line, '#' ) eq 0 ) {
                next;
            }

            if ( $line =~ s/^\s*dbexec\s+.*?-rollback\s+// ) {
                $isRollback = 1;
                $ENV{IS_SQL_ROLLBACK} = 1;
            }
        }
    }

    return $isRollback;
}

sub exec {
    my ( $self, $sqlFile, $envPath, $version, $isVerbose ) = @_;

    my $envInfo = ENVInfo::parse( $envPath, $version );

    my $shareStatus = $envInfo->{'sql.sharestatus'};
    if ( defined($shareStatus) and $shareStatus eq 'true' ) {
        $ENV{SQL_SHARE_STATUS} = 1;
        $self->{shareStatus} = 1;
    }
    else {
        $ENV{SQL_SHARE_STATUS} = 0;
    }

    my $scope  = $ENV{SCOPE};
    my $ticket = $ENV{TICKET_ID};

    if ( not defined($scope) ) {
        $scope = 'ticket';
    }
    if ( not defined($ticket) or $ticket eq '' ) {
        $ticket = '00000000';
    }

    my $bookItem = $ENV{PLAYBOOK};

    #my $sqlFile       = $ENV{SQL};
    my $parallelCount = $ENV{PARALLEL_COUNT};
    if ( not defined($parallelCount) ) {
        $parallelCount = 1;
    }

    my $timeSpan = $ENV{TIME_SPAN};
    if ( not defined($timeSpan) ) {
        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
        $timeSpan = sprintf( "%04d%02d%02d-%02d%02d%02d-%d", $year + 1900, $mon + 1, $mday, $hour, $min, $sec, $$ );
    }

    my $logRelPath = "$bookItem.$ticket.$timeSpan.log";
    my $logPath    = $envInfo->{versdir} . '/' . $version . '.logs';
    my $statusPath = $envInfo->{distressrc} . "/db.status";

    my $logPrefix = sprintf( "%s.%s", $bookItem, $ticket );
    my $runStatus = new RunStatus( $logPath, $logPrefix, $timeSpan );
    my $runBatch = new RunBatch( $envPath, $version );

    my $bookPath = $runBatch->getEnvPlaybook($bookItem);

    my $isSqlRollback = $ENV{IS_SQL_ROLLBACK};
    if ( not defined($isSqlRollback) or $isSqlRollback eq '' ) {
        $isSqlRollback = $self->checkIfRollback($bookPath);
    }

    my $isRunAll = 0;
    my $filter;
    my $index;
    my $allSqlFiles;
    my $sqlFilesToRun = [];

    my $isFail  = 0;
    my $gStatus = 'failed';

    eval {
        $self->parseSqlPluginOpts($bookPath);
        $index  = $self->{index};
        $filter = $self->{filter};
        if ( $self->{shareStatus} == 1 ) {
            $statusPath = $envInfo->{envdbstatuslog};
        }
        $self->{statusRootPath} = $statusPath;

        if ( defined($isSqlRollback) and $isSqlRollback ne '' ) {
            if ( defined($index) ) {
                $allSqlFiles = $runBatch->getSqlFilePathByIdx( $index, 'rollback' );
            }
            else {
                $allSqlFiles = $runBatch->getAllSqlFilePath('rollback');
            }
        }
        else {
            if ( defined($filter) and $filter ne '' ) {
                if ( defined($index) ) {
                    $allSqlFiles = $runBatch->getSqlFilePathByIdx( $index, $filter );
                }
                else {
                    $allSqlFiles = $runBatch->getAllSqlFilePath($filter);
                }
            }
            else {
                if ( defined($index) ) {
                    $allSqlFiles = $runBatch->getSqlFilePathByIdx($index);
                }
                else {
                    $allSqlFiles = $runBatch->getAllSqlFilePath();
                }
            }
        }

        if ( not defined($sqlFile) ) {
            $isRunAll      = 1;
            $sqlFilesToRun = $allSqlFiles;
        }
        else {
            my @sqlFiles = split( /\s*,\s*/, $sqlFile );
            foreach my $tmpFile (@sqlFiles) {
                push( @$sqlFilesToRun, $tmpFile );
            }
        }

        ServerAdapter::callback( 'running', $scope, $ticket, $bookItem, $logRelPath, $envInfo->{sys}, $envInfo->{subsys}, $envInfo->{version}, $envInfo->{env} );

        $isFail = $self->sqlexec( $scope, $runBatch, $envInfo, $bookPath, $bookItem, $ticket, $sqlFilesToRun, $logPath, $parallelCount );

        $gStatus = $self->sqlexecStatus( $scope, $allSqlFiles, $statusPath, $logPath, $ticket, $bookItem );
    };
    if ($@) {
        print("ERROR: $@\n");
        $isFail = 1;
    }

    if ( $isFail ne 0 ) {
        if ( $gStatus eq 'succeed' ) {
            $gStatus = 'failed';
        }
        elsif ( $gStatus eq 'running' ) {
            $gStatus = 'aborted';
        }

        print("ERROR: $bookItem $gStatus================\n");
    }

    print("INFO: callback with status:$gStatus=============\n");

    $runStatus->endWithStatus($gStatus);
    ServerAdapter::callback( $gStatus, $scope, $ticket, $bookItem, $logRelPath, $envInfo->{sys}, $envInfo->{subsys}, $envInfo->{version}, $envInfo->{env} );

    return $isFail;
}

1;

