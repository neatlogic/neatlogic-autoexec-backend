#!/usr/bin/perl
use strict;

package SYBASESQLRunner;

use FindBin;
use Expect;
use Encode;
use File::Temp;
use File::Basename;

use DeployUtils;
use SQLFileStatus;

sub new {
    my ( $pkg, $sqlFile, %args ) = @_;

    my $sqlFileStatus = $args{sqlFileStatus};
    my $dbInfo        = $args{dbInfo};
    my $charSet       = $args{charSet};
    my $logFilePath   = $args{logFilePath};
    my $toolsDir      = $args{toolsDir};
    my $tmpDir        = $args{tmpDir};
    my $isInteract    = $args{isInteract};

    my $dbType       = $dbInfo->{dbType};
    my $dbName       = $dbInfo->{sid};
    my $host         = $dbInfo->{host};
    my $port         = $dbInfo->{port};
    my $user         = $dbInfo->{user};
    my $pass         = $dbInfo->{pass};
    my $isAutoCommit = $dbInfo->{autocommit};
    my $dbVersion    = $dbInfo->{version};
    my $dbArgs       = $dbInfo->{args};

    my $deployUtils = DeployUtils->new();
    $user = $deployUtils->escapeQuote($user);
    $pass = $deployUtils->escapeQuote($pass);

    my $self = {};
    bless( $self, $pkg );

    $sqlFile =~ s/^\s*'|'\s*$//g;

    $self->{sqlFileStatus} = $sqlFileStatus;
    $self->{toolsDir}      = $toolsDir;
    $self->{tmpDir}        = $tmpDir;

    $self->{dbType}       = $dbType;
    $self->{host}         = $host;
    $self->{port}         = $port;
    $self->{sqlFile}      = $sqlFile;
    $self->{charSet}      = $charSet;
    $self->{user}         = $user;
    $self->{pass}         = $pass;
    $self->{logFilePath}  = $logFilePath;
    $self->{isAutoCommit} = $isAutoCommit;

    $self->{PROMPT}       = qr/1> $/is;
    $self->{hasLogon}     = 0;
    $self->{ignoreErrors} = $dbInfo->{ignoreErrors};
    $self->{warningCount} = 0;
    $self->{logonTimeout} = $dbInfo->{logonTimeout};

    if ( not defined($isInteract) ) {
        $isInteract = 0;
    }
    $self->{isInteract} = $isInteract;

    if ( $charSet eq 'UTF-8' ) {
        $ENV{LANG} = 'en_US.UTF8';

        #$ENV{LC_ALL} = 'en_US.UTF8';
    }
    else {
        $ENV{LANG} = 'en_US.GBK';

        #$ENV{LC_ALL} = 'en_US.GBK';
    }

    my $sybaseHome = "$toolsDir/sybase-client";
    if ( defined($dbVersion) and -e "$sybaseHome-$dbVersion" ) {
        $sybaseHome = "$sybaseHome-$dbVersion";
    }

    $ENV{SYBASE_HOME} = $sybaseHome;
    $ENV{SYBASE}      = $sybaseHome;
    $ENV{PATH}        = "$sybaseHome/bin:" . $ENV{PATH};

    my $sqlDir      = dirname($sqlFile);
    my $sqlFileName = basename($sqlFile);
    $self->{sqlFileName} = $sqlFileName;

    my $tmp     = File::Temp->new( DIR => $tmpDir, UNLINK => 1, SUFFIX => '.sybase' );
    my $content = "SYBASEDB\n\tmaster tcp ether $host $port\n\tquery tcp ether $host $port\n";
    print $tmp ($content);
    my $interfaceFile = $tmp->filename;
    $tmp->flush();
    $self->{SYBASE_INTERFACE_TMP} = $tmp;

    chdir($sqlDir);

    print(qq{INFO: isql -e -I $interfaceFile -U "$user" -P "******" -S SYBASEDB -D "$dbName"\n});

    my $spawn = Expect->spawn(qq{isql -e -I $interfaceFile -U "$user" -P "$pass" -S SYBASEDB -D "$dbName"});

    if ( not defined($spawn) ) {
        die("launch sybase client isql failed, check if it exists and it's permission.\n");
    }

    #$spawn->debug(1);
    $spawn->max_accum(2048);

    $self->{spawn} = $spawn;

    return $self;
}

sub test {
    my ($self) = @_;

    my $host         = $self->{host};
    my $port         = $self->{port};
    my $user         = $self->{user};
    my $password     = $self->{pass};
    my $dbName       = $self->{dbName};
    my $logonTimeout = $self->{logonTimeout};

    my $PROMPT = $self->{PROMPT};

    my $spawn = $self->{spawn};
    $spawn->log_stdout(0);

    my $hasLogon = 0;
    $spawn->expect(
        $logonTimeout,
        [
            qr/Msg\s+\d+,\s+Level\s+\d+,\s+State\s+\d+:\s*\n.*?(?=\d>\s)/is => sub {
                print( $spawn->before() );
                print( $spawn->match() );
                $spawn->send("quit\n");
            }
        ],
        [
            timeout => sub {
                print("ERROR: Connection timeout(exceed $logonTimeout seconds).\n");
            }
        ],
        [
            eof => sub {

                #print( DeployUtils->convToUTF8( $spawn->before() ) );
            }
        ],
        [
            $PROMPT => sub {
                $hasLogon = 1;
                $spawn->send("quit\n");
            }
        ]
    );

    $spawn->soft_close();

    if ( $hasLogon == 1 ) {
        $self->{hasLogon} = 1;
        print("INFO: sybase $user\@//$host:$port/$dbName connection test success.\n");
    }
    else {
        print("ERROR: sybase $user\@//$host:$port/$dbName connection test failed.\n");
    }

    return $hasLogon;
}

sub run {
    my ($self)       = @_;
    my $password     = $self->{pass};
    my $spawn        = $self->{spawn};
    my $logFilePath  = $self->{logFilePath};
    my $charSet      = $self->{charSet};
    my $sqlFile      = $self->{sqlFile};
    my $sqlFileName  = $self->{sqlFileName};
    my $isAutoCommit = $self->{isAutoCommit};
    my $sqlFile      = $sqlFileName;

    my $pipeFile = $logFilePath;
    $pipeFile =~ s/\.log$//;
    $pipeFile = "$pipeFile.run.pipe";

    #my $PROMPT = qr/1> $/is;
    my $PROMPT = $self->{PROMPT};

    my $hasSendPassword   = 0;
    my $hasSendAutocommit = 0;
    my $hasSendSql        = 0;
    my $hasRunSql         = 0;
    my ( $sqlError, $sqlErrMsg );
    my $sessionKilled = 0;
    my $hasWarn       = 0;
    my $hasError      = 0;
    my $hasHardError  = 0;
    my $sqlexecStatus = 0;
    my $warningCount  = 0;

    my $ignoreErrors = $self->{ignoreErrors};

    my $isFail = 0;

    my $execEnded = sub {

        #session被kill
        if ( $hasHardError == 1 or $sessionKilled == 1 ) {
            $isFail = 1;
        }

        #ORA 错误
        elsif ( $hasError == 1 ) {
            print("\nERROR: some error occurred, check the log for detail.\n");

            my $opt;

            if ( $isAutoCommit == 1 ) {
                print("\nWARN: autocommit is on, select 'ignore' to continue, 'abort' to abort the job.\n");
                if ( $self->{isInteract} == 1 ) {
                    my $sqlFileStatus = $self->{sqlFileStatus};
                    $opt = $sqlFileStatus->waitInput( 'Execute failed, select action(ignore|abort)', $pipeFile );
                }

                $opt = 'abort' if ( not defined($opt) );

                if ( $opt eq 'abort' ) {
                    $isFail = 1;
                }
                $spawn->send("quit\n");
                $spawn->soft_close();
            }
            else {
                if ( $self->{isInteract} == 1 ) {
                    my $sqlFileStatus = $self->{sqlFileStatus};
                    $opt = $sqlFileStatus->waitInput( 'Running with error, please select action(commit|rollback)', $pipeFile );
                }

                $opt = 'rollback' if ( not defined($opt) );

                $spawn->send("$opt\n");
                $spawn->expect( undef, [ qr/\d+> $/ => sub { } ] );
                $spawn->send("go\n");
                $spawn->expect( undef, [ qr/\d+> $/ => sub { } ] );
                $spawn->send("quit\n");
                $spawn->soft_close();

                if ( $opt eq 'rollback' ) {
                    $isFail = 1;
                }
            }
        }
        else {
            if ( not $isAutoCommit == 1 ) {
                $spawn->send("commit\n");
                $spawn->expect( undef, [ qr/\d+> $/ => sub { } ] );
                $spawn->send("go\n");
                $spawn->expect( undef, [ qr/\d+> $/ => sub { } ] );
            }

            $spawn->send("quit\n");
            $spawn->soft_close();
        }

        $sqlexecStatus = $spawn->exitstatus();

        #段错误, sqlplus bug
        if ( defined($sqlexecStatus) and $sqlexecStatus != 0 ) {
            print("ERROR: isql exit abnormal.\n");

            $isFail = 1;
        }
    };

    #expect pattern的顺序至关重要，如果要调整这里的match顺序，必须全部场景都要测试，场景包括
    #1）用户密码错误
    #2）主机IP端口错误
    #3）DB名称错误
    #4）SQL语法错误
    #5）不存在的SQL对象
    #6) sql脚本不存在
    #7）session killed
    #8）执行sql的命令不存在（譬如：sqlplus(oracle)不存在，clpplus(db2)不存在）
    my $logonTimeout = $self->{logonTimeout};
    my $hasLogon     = 0;
    $spawn->expect(
        $logonTimeout,
        [
            qr/Msg\s+\d+,\s+Level\s+\d+,\s+State\s+\d+:\s*\n.*?(?=\d>\s)/is => sub {
                $hasHardError = 1;
                $hasError     = 1;
                $spawn->send("quit\n");
                $spawn->expect(undef);
                &$execEnded();
            }
        ],
        [
            eof => sub {
                $sqlErrMsg = $spawn->before();

                #IP or Port error
                #CT-LIBRARY error:
                #        ct_connect(): network packet layer: internal net library error: Net-Lib protocol driver call to connect two endpoints failed
                #Session Killed
                #CT-LIBRARY error:
                #        ct_results(): network packet layer: internal net library error: Net-Library operation terminated due to disconnect
                $hasHardError = 1 if ( $sqlErrMsg =~ /^CT-LIBRARY error:/is );
                $sqlErrMsg =~ s/\r|\n/ /g;

                &$execEnded();
            }
        ],
        [
            timeout => sub {
                print("ERROR: Connection timeout(exceed $logonTimeout seconds).\n");
                $hasHardError = 1;
                $hasError     = 1;
                &$execEnded();
            }
        ],
        [
            $PROMPT => sub {
                $hasLogon = 1;
            }
        ]
    );

    if ( $hasLogon == 1 ) {
        print("Execution start > ");

        if ( $isAutoCommit == 1 ) {
            $spawn->send("set chained off\n");
        }
        else {
            $spawn->send("set chained on\n");
        }

        $spawn->expect( undef, [ qr/\d+> $/ => sub { } ] );
        $spawn->send("go\n");

        $spawn->expect( undef, [ $PROMPT => sub { } ] );

        $self->{hasLogon} = 1;
        $spawn->send(":r $sqlFile\n");
        $spawn->expect( undef, [ qr/\d+> $/ => sub { } ] );
        $spawn->send("go\n");

        $spawn->expect(
            undef,
            [

                #Msg 2601, Level 14, State 2:
                #Server 'SITDEPLOY24', Line 1:
                #Attempt to insert duplicate key row in object 'EX_USER' with unique index
                #'EX_USER_19196982052'
                #Command has been aborted.
                #(0 rows affected)
                #qr/(?<=\n)Msg\s+\d+,\s+Level\s+\d+,\s+State\s+\d+:\n.*?\n(?=1>\s)/is => sub {
                qr/Msg\s+\d+,\s+Level\s+\d+,\s+State\s+\d+:\s*\n.*?(?=\d>\s)/is => sub {
                    my $matchContent = DeployUtils->convToUTF8( $spawn->match() );
                    my $nwPos        = index( $matchContent, "\n" );
                    $sqlError  = substr( $matchContent, 0, $nwPos - 1 );
                    $sqlErrMsg = $matchContent;
                    $sqlErrMsg =~ s/\r|\n/ /g;

                    $warningCount = $warningCount + 1;

                    #如果错误可忽略则输出警告，否则输出错误
                    if ( $ignoreErrors =~ /$sqlError/ ) {
                        $hasWarn = 1;
                    }
                    else {
                        $hasError = 1;
                        print("ERROR: $matchContent\n");

                        if ( index( $sqlErrMsg, 'Attempt to locate entry in sysdatabases for database' ) > 0 ) {
                            $hasHardError = 1;
                            $spawn->send("quit\n");
                        }
                    }
                    $spawn->exp_continue;
                }
            ],
            [
                $PROMPT => sub {
                    &$execEnded();
                }
            ],
            [
                eof => sub {
                    $hasHardError = 1;
                    $hasError     = 1;
                    &$execEnded();
                }
            ]
        );
    }

    $self->{warningCount} = $warningCount;

    return $isFail;
}

1;

