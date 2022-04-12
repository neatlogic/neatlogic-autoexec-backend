#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

package MONGODBSQLRunner;

use strict;
use DeployUtils;
use Encode;
use File::Basename;

sub new {
    my ( $pkg, $dbInfo, $sqlCmd, $charSet, $logFilePath ) = @_;

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

    $pkg = ref($pkg) || $pkg;
    unless ($pkg) {
        $pkg = "MONGODBSQLRunner";
    }

    my $self = {};
    bless( $self, $pkg );

    $self->{dbType}       = $dbType;
    $self->{dbName}       = $dbName;
    $self->{host}         = $host;
    $self->{port}         = $port;
    $self->{sqlCmd}       = $sqlCmd;
    $self->{charSet}      = $charSet;
    $self->{user}         = $user;
    $self->{pass}         = $pass;
    $self->{logFilePath}  = $logFilePath;
    $self->{isAutoCommit} = $isAutoCommit;

    $self->{PROMPT}       = ':PRIMARY>\s$';
    $self->{hasLogon}     = 0;
    $self->{ignoreErrors} = $dbInfo->{ignoreErrors};

    if ( defined($sqlCmd) and $sqlCmd ne '' and $sqlCmd ne 'test' ) {
        my $sqlDir      = dirname($sqlCmd);
        my $sqlFileName = basename($sqlCmd);
        $self->{sqlFileName} = $sqlFileName;
        chdir($sqlDir);
    }

    my $deploysysHome;
    if ( exists $ENV{DEPLOYSYS_HOME} ) {
        $deploysysHome = $ENV{DEPLOYSYS_HOME};
    }
    else {
        $deploysysHome = Cwd::abs_path("$FindBin::Bin/..");
    }

    my $mongoHome = "$deploysysHome/tools/mongodb-shell";
    if ( defined($dbVersion) and -e "$mongoHome-$dbVersion" ) {
        $mongoHome = "$mongoHome-$dbVersion";
    }

    $ENV{PATH} = "$mongoHome/bin:" . $ENV{PATH};

    $dbStr =~ s/mongodb\///;
    print("INFO: mongondb://$dbStr\n");

    my $cmd;
    if ( $user eq 'anonymous' or $pass eq '' ) {
        $cmd = "mongo mongodb://$dbStr";
    }
    else {
        $cmd = "mongo mongodb://$user:$pass\@$dbStr";
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

    my $dbStr  = $self->{dbStr};
    my $user   = $self->{user};
    my $PROMPT = $self->{PROMPT};

    my $hasHardError = 0;
    my $hasLogon     = 0;

    $spawn->expect(
        15,
        [
            qr/$PROMPT/ => sub {
                $hasLogon = 1;
                $spawn->send("exit;\n");
                }
        ],
        [
            eof => sub {
                $hasHardError = 1;
                print( DeployUtils->convToUTF8( $spawn->before() ) );
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
    my $sqlCmd      = $self->{sqlCmd};
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
            print("\nERROR: some error occurred, check the log for detail.\n");

            if ( $autocommit == 0 ) {
                my $opt;
                if ( exists( $ENV{IS_INTERACT} ) ) {
                    $opt = DeployUtils->decideOption( 'Running with error, please select action(commit|rollback)', $pipeFile );
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
            print("ERROR: mongodb exit abnormal.\n");

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

    my $hasLogon = 0;
    $spawn->expect(
        20,
        [
            qr/$PROMPT/ => sub {
                $hasLogon = 1;
                }
        ],
        [
            timeout => sub {
                print("ERROR: connection timeout.\n");
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

    $ENV{WARNING_COUNT} = $warningCount;
    $ENV{HAS_ERROR}     = $hasError;

    return $isFail;
}

1;

