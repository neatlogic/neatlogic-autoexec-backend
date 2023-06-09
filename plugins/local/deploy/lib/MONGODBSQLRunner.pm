#!/usr/bin/perl
use strict;

package MONGODBSQLRunner;

use FindBin;
use Expect;
use Encode;
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

    my $dbStr        = $dbInfo->{dbStr};
    my $dbType       = $dbInfo->{dbType};
    my $dbName       = $dbInfo->{sid};
    my $host         = $dbInfo->{host};
    my $port         = $dbInfo->{port};
    my $user         = $dbInfo->{user};
    my $pass         = $dbInfo->{pass};
    my $isAutoCommit = $dbInfo->{autocommit};
    my $dbVersion    = $dbInfo->{version};
    my $dbArgs       = $dbInfo->{args};
    my $dbLocale     = $dbInfo->{locale};

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
    $self->{dbName}       = $dbName;
    $self->{host}         = $host;
    $self->{port}         = $port;
    $self->{sqlFile}      = $sqlFile;
    $self->{charSet}      = $charSet;
    $self->{user}         = $user;
    $self->{pass}         = $pass;
    $self->{logFilePath}  = $logFilePath;
    $self->{isAutoCommit} = $isAutoCommit;

    $self->{PROMPT}       = ':PRIMARY>\s$';
    $self->{hasLogon}     = 0;
    $self->{ignoreErrors} = $dbInfo->{ignoreErrors};
    $self->{warningCount} = 0;
    $self->{logonTimeout} = $dbInfo->{logonTimeout};

    if ( not defined($isInteract) ) {
        $isInteract = 0;
    }
    $self->{isInteract} = $isInteract;

    if ( defined($sqlFile) and $sqlFile ne '' ) {
        my $sqlDir      = dirname($sqlFile);
        my $sqlFileName = basename($sqlFile);
        $self->{sqlFileName} = $sqlFileName;
        chdir($sqlDir);
    }

    my $mongoHome = "$toolsDir/mongodb-shell";
    if ( defined($dbVersion) and -e "$mongoHome-$dbVersion" ) {
        $mongoHome = "$mongoHome-$dbVersion";
    }

    $ENV{PATH} = "$mongoHome/bin:" . $ENV{PATH};

    $dbStr =~ s/mongodb\///;
    print("INFO: Mongondb://$dbStr\n");

    my $cmd;
    if ( $user eq 'anonymous' or $pass eq '' ) {
        $cmd = "mongo mongodb://$dbStr";
    }
    else {
        $cmd = qq{mongo "mongodb://$user:$pass\@$dbStr"};
    }

    my $spawn = Expect->spawn($cmd);

    if ( not defined($spawn) ) {
        die("launch mongo shell client failed, check if it exists and it's permission.\n");
    }

    $spawn->max_accum(2048);

    $self->{spawn} = $spawn;

    return $self;
}

sub test {
    my ($self) = @_;

    my $spawn = $self->{spawn};
    $spawn->log_stdout(0);

    my $dbStr        = $self->{dbStr};
    my $user         = $self->{user};
    my $PROMPT       = $self->{PROMPT};
    my $logonTimeout = $self->{logonTimeout};

    my $hasHardError = 0;
    my $hasLogon     = 0;

    $spawn->expect(
        $logonTimeout,
        [
            qr/$PROMPT/ => sub {
                $hasLogon = 1;
                $spawn->send("exit;\n");
            }
        ],
        [
            timeout => sub {
                print("ERROR: Connection timeout(exceed $logonTimeout seconds).\n");
            }
        ],
        [
            eof => sub {
                if ( $hasLogon != 1 ) {
                    print( DeployUtils->convToUTF8( $spawn->before() ) );
                }
            }
        ]
    );

    $spawn->soft_close();

    $dbStr =~ s/^mongodb\//mongodb:\/\/$user\@/;
    if ( $hasLogon == 1 ) {
        $self->{hasLogon} = 1;
        print("INFO: $dbStr connection test success.\n");
    }
    else {
        my $errMsg = DeployUtils->convToUTF8( $spawn->before() );
        print($errMsg );
        print("ERROR: $dbStr connection test failed.\n");
    }

    return $hasLogon;
}

sub run {
    my ($self)      = @_;
    my $spawn       = $self->{spawn};
    my $dbName      = $self->{dbName};
    my $logFilePath = $self->{logFilePath};
    my $charSet     = $self->{charSet};
    my $sqlFile     = $self->{sqlFile};
    my $sqlFileName = $self->{sqlFileName};
    my $repSet      = $self->{repSet};
    my $autocommit  = $self->{isAutoCommit};

    my $PROMPT = $self->{PROMPT};

    my $pipeFile = $logFilePath;
    $pipeFile =~ s/\.log$//;
    $pipeFile = "$pipeFile.run.pipe";

    my $hasSendCharset = 0;
    my $hasSendSql     = 0;
    my ( $sqlError, $sqlErrMsg );
    my $sessionKilled = 0;
    my $hasWarn       = 0;
    my $hasError      = 0;
    my $hasHardError  = 0;
    my $sqlexecStatus = 0;
    my $warningCount  = 0;

    my $ignoreErrors = $self->{ignoreErrors};

    my $isFail = 0;
    my $errMsg = "\n";

    my $execEnded = sub {

        #session被kill
        if ( $hasHardError == 1 or $sessionKilled == 1 ) {
            $isFail = 1;
        }

        #ORA 错误
        elsif ( $hasError == 1 ) {
            print($errMsg) if ( $errMsg ne "\n" );
            $isFail = 1;
            print("\nERROR: Some error occurred, check the log for detail.\n");

            if ( $autocommit == 0 ) {
                my $opt;
                if ( $self->{isInteract} == 1 ) {
                    my $sqlFileStatus = $self->{sqlFileStatus};
                    $opt = $sqlFileStatus->waitInput( 'Running with error, please select action(commit|rollback)', $pipeFile );
                }

                $opt = 'rollback' if ( not defined($opt) );

                if ( $opt eq "commit" ) {
                    $spawn->send("session.commitTransaction()\n");
                    $isFail = 0;
                }
                else {
                    $spawn->send("session.abortTransaction()\n");
                }
                $spawn->expect( undef, [ qr/$PROMPT/ => sub { } ] );
            }

        }
        else {
            if ( $autocommit == 0 ) {
                $spawn->send("session.commitTransaction()\n");
                $spawn->expect(
                    undef,
                    [
                        qr/Error/ => sub {
                            $isFail = 1;
                        }
                    ],
                    [ qr/$PROMPT/ => sub { } ]
                );
            }
        }

        $spawn->send("session.endSession()\n");
        $spawn->expect( undef, [ qr/$PROMPT/ => sub { } ] );
        $spawn->send("exit\n");
        $spawn->soft_close();

        $sqlexecStatus = $spawn->exitstatus();

        #段错误, sqlplus bug
        if ( defined($sqlexecStatus) and $sqlexecStatus != 0 ) {
            print("ERROR: Mongodb exit abnormal.\n");

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
            qr/$PROMPT/ => sub {
                $hasLogon = 1;
            }
        ],
        [
            timeout => sub {
                print("ERROR: Connection timeout(exceed $logonTimeout seconds).\n");
                $hasHardError = 1;
                &$execEnded();
            }
        ],
        [
            eof => sub {
                my $errMsg = DeployUtils->convToUTF8( $spawn->before() );
                print( "ERROR: ", $errMsg );
                $hasHardError = 1;
                &$execEnded();
            }
        ]
    );

    if ( $hasLogon == 1 ) {
        $self->{hasLogon} = 1;
        print("Execution start > ");

        $spawn->send("session = db.getMongo().startSession( { readPreference: { mode: \"primary\" } } )\n");
        $spawn->expect(
            undef,
            [
                qr/Error/ => sub {
                    $hasError = 1;
                    $spawn->exp_continue();
                }
            ],
            [
                qr/$PROMPT/ => sub {
                }
            ],
            [
                eof => sub {
                    $hasHardError = 1;
                    &$execEnded();
                }
            ]
        );

        if ( $hasError != 1 and $hasHardError != 1 ) {
            if ( $autocommit == 0 ) {
                $spawn->send("session.startTransaction( { readConcern: { level: \"snapshot\" }, writeConcern: { w: \"majority\" } } )\n");
                $spawn->expect(
                    undef,
                    [
                        qr/Error/ => sub {
                            $hasError = 1;
                            $spawn->exp_continue();
                        }
                    ],
                    [
                        qr/$PROMPT/ => sub {
                        }
                    ],
                    [
                        eof => sub {
                            $hasHardError = 1;
                            &$execEnded();
                        }
                    ]
                );
            }

            if ( $hasError != 1 and $hasHardError != 1 ) {
                $spawn->send("load(\"$sqlFileName\")\n");
                $spawn->expect(
                    undef,
                    [
                        qr/Error/ => sub {
                            $hasError = 1;
                            $spawn->exp_continue();
                        }
                    ],
                    [
                        qr/$PROMPT/ => sub {
                            &$execEnded();
                        }
                    ],
                    [
                        eof => sub {
                            $hasHardError = 1;
                            &$execEnded();
                        }
                    ]
                );
            }
        }
    }

    $self->{warningCount} = $warningCount;

    return $isFail;
}

1;

