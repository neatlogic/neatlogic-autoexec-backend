#!/usr/bin/perl
use strict;

package HANASQLRunner;

use FindBin;
use Expect;
use Encode;
use File::Basename;
use Cwd;
use File::Temp;

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

    my $dbType         = $dbInfo->{dbType};
    my $dbName         = $dbInfo->{sid};
    my $host           = $dbInfo->{host};
    my $port           = $dbInfo->{port};
    my $user           = $dbInfo->{user};
    my $pass           = $dbInfo->{pass};
    my $isAutoCommit   = $dbInfo->{autocommit};
    my $dbVersion      = $dbInfo->{version};
    my $dbArgs         = $dbInfo->{args};
    my $dbServerLocale = $dbInfo->{locale};

    my $deployUtils = DeployUtils->new();
    $user = $deployUtils->escapeQuote($user);
    $pass = $deployUtils->escapeQuote($pass);

    my $self = {};
    bless( $self, $pkg );

    my $hanaClientDir = 'hana-client';
    if ( defined($dbVersion) and -e "$toolsDir/hana-client-$dbVersion" ) {
        $hanaClientDir = "hana-client-$dbVersion";
    }

    $ENV{HANA_HOME}       = "$toolsDir/$hanaClientDir";
    $ENV{LD_LIBRARY_PATH} = $ENV{HANA_HOME} . $ENV{LD_LIBRARY_PATH};
    $ENV{PATH}            = "$toolsDir/$hanaClientDir" . ':' . $ENV{PATH};

    if ( defined($dbServerLocale) and ( $dbServerLocale eq 'ISO-8859-1' or $dbServerLocale =~ /\.WE8ISO8859P1/ ) ) {
        $ENV{NLS_LANG} = 'AMERICAN_AMERICA.WE8ISO8859P1';
    }
    else {
        if ( $charSet eq 'UTF-8' ) {
            $ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
        }
        elsif ( $charSet eq 'GBK' ) {
            $ENV{NLS_LANG} = 'AMERICAN_AMERICA.ZHS16GBK';
        }
    }

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
    $self->{dbName}       = $dbName;
    $self->{dbVersion}    = $dbVersion;
    $self->{dbArgs}       = $dbArgs;

    $self->{PROMPT}       = qr/\nhdbsql $dbName=> $/s;
    $self->{hasLogon}     = 0;
    $self->{ignoreErrors} = $dbInfo->{ignoreErrors};
    $self->{warningCount} = 0;
    $self->{logonTimeout} = $dbInfo->{logonTimeout};

    if ( not defined($isInteract) ) {
        $isInteract = 0;
    }
    $self->{isInteract} = $isInteract;

    my $spawn;

    my $sqlDir      = dirname($sqlFile);
    my $sqlFileName = basename($sqlFile);
    $self->{sqlFileName} = $sqlFileName;

    chdir($sqlDir);

    if ( $sqlFile =~ /\.model/i ) {
        print("INFO: Filetype:model\n");
        $ENV{REGI_HOST}   = "$host:$port";
        $ENV{REGI_USER}   = $user;
        $ENV{REGI_PASSWD} = $pass;

        $self->{fileType} = 'MODEL';

    }
    else {
        $self->{fileType} = 'SQL';

        print("INFO: Filetype:sql\n");
        print(qq{INFO: Hdbsql -u "$user" -p "******" -n $host:$port -d "$dbName" $dbArgs\n});
        $spawn = Expect->spawn(qq{hdbsql -u "$user" -p "$pass" -n $host:$port -d "$dbName" $dbArgs});
        if ( not defined($spawn) ) {
            die("launch hana client failed, check if it exists and it's permission.\n");
        }
        $spawn->max_accum(2048);
        $self->{spawn} = $spawn;
    }

    return $self;
}

sub test {
    my ($self) = @_;

    my $hasLogon     = 0;
    my $hasHardError = 0;

    my $spawn        = $self->{spawn};
    my $PROMPT       = $self->{PROMPT};
    my $host         = $self->{host};
    my $port         = $self->{port};
    my $dbName       = $self->{dbName};
    my $user         = $self->{user};
    my $logonTimeout = $self->{logonTimeout};

    $spawn->log_stdout(0);

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

    if ( $hasLogon == 1 ) {
        $self->{hasLogon} = 1;
        print("INFO: Hdbsql -u $user -p ******* -n $host:$port -d $dbName \n");
    }
    else {
        print( $spawn->before() );
        print("ERROR: Hdbsql -u $user -p ******* -n $host:$port -d $dbName connection test failed.\n");
    }

    return $hasLogon;
}

sub run {
    my ($self)       = @_;
    my $spawn        = $self->{spawn};
    my $logFilePath  = $self->{logFilePath};
    my $charSet      = $self->{charSet};
    my $sqlFile      = $self->{sqlFile};
    my $user         = $self->{user};
    my $pass         = $self->{pass};
    my $dbName       = $self->{dbName};
    my $fileType     = $self->{fileType};
    my $isAutoCommit = $self->{isAutoCommit};

    my $pipeFile = $logFilePath;
    $pipeFile =~ s/\.log$//;
    $pipeFile = "$pipeFile.run.pipe";

    my $PROMPT = $self->{PROMPT};

    my ( $sqlError, $sqlErrMsg );
    my $sessionKilled = 0;
    my $hasWarn       = 0;
    my $hasError      = 0;
    my $hasHardError  = 0;
    my $sqlplusStatus = 0;
    my $warningCount  = 0;

    my $ignoreErrors = $self->{ignoreErrors};

    my $isFail = 0;

    my $execEnded = sub {

        #session被kill
        if ( $hasHardError == 1 or $sessionKilled == 1 ) {

            $isFail = 1;
            unlink("myWS");
        }
        elsif ( $hasError == 1 || $hasWarn == 1 ) {

            if ( $fileType eq 'MODEL' ) {

                $ENV{REGI_HOST}   = '';
                $ENV{REGI_USER}   = '';
                $ENV{REGI_PASSWD} = '';

                unlink("myWS");
            }
            else {
                if ( $isAutoCommit == 0 ) {
                    my $opt;
                    if ( $self->{isInteract} == 1 ) {
                        my $sqlFileStatus = $self->{sqlFileStatus};
                        $opt = $sqlFileStatus->waitInput( 'Running with error, please select action(commit|rollback)', $pipeFile );
                    }

                    $opt = 'rollback' if ( not defined($opt) );

                    if ( $opt eq "commit" ) {
                        $spawn->send("commit\n");
                        $isFail = 0;
                    }
                    else {
                        $spawn->send("rollback\n");
                    }
                    $spawn->expect( undef, [ qr/$PROMPT/ => sub { } ] );
                }
                $spawn->send("\\q\n");
                $spawn->expect(undef);
            }

            print("\nERROR: Some error occurred, check the log for detail.\n");

            $isFail = 1;
        }
    };

    my $sqlDir = dirname($sqlFile);
    if ( $sqlDir ne '' ) {
        chdir($sqlDir);
    }

    if ( $fileType eq 'MODEL' ) {

        my $TMPDIR      = $self->{tmpDir};
        my $zipFileName = $self->{sqlFileName};
        my $tmp         = File::Temp->new( DIR => $TMPDIR );
        my $zipTmpDir   = $tmp->newdir( DIR => $TMPDIR );
        my $pwd         = Cwd::getcwd();

        print("INFO: Unzip -qd '$zipTmpDir' $zipFileName >/dev/null 2>\&1\n");
        my $ret = DeployUtils->execmd("unzip -qd $zipTmpDir $sqlDir/$zipFileName >/dev/null 2>\&1");

        if ( $ret eq 0 ) {
            print("INFO: Zip file $zipFileName success.\n");
        }
        else {
            print("ERROR: Unzip file $zipFileName failed.\n");
            $hasError = 1;
            &$execEnded();
        }

        $zipFileName =~ s/^.zip//;

        my @files = glob("$zipTmpDir/$zipFileName/*");
        my $cmd;

        if ( $ret eq 0 ) {
            print("INFO : create workspace myWS success\n");
            print("INFO: Regi create workspace myWS\n");
            $cmd = "regi create workspace myWS";
            $ret = DeployUtils->execmd($cmd);
        }
        else {
            print("ERROR: Create workspace myWS failed\n");
            $hasHardError = 1;
            &$execEnded();
        }

        if ( $ret eq 0 ) {
            foreach (@files) {
                print("INFO: Regi checkOut $_\n");
                $cmd = "regi checkOut $_";
                $ret = DeployUtils->execmd($cmd);
                if ( $ret eq 0 ) {
                    print("INFO: Checkout package $_ success\n");
                    print("INFO: Cp -r $zipTmpDir/$zipFileName/* myWS/");
                    $ret = DeployUtils->execmd("cp -r $zipTmpDir/$zipFileName/* myWS/");
                }
                else {
                    print("ERROR: Checkout package $_ failed\n");
                    $hasHardError = 1;
                    &$execEnded();
                }
            }
        }

        if ( $ret eq 0 ) {
            print("INFO : copy packages to myWS success\n");
            print("INFO: Regi push\n");
            $cmd = "regi push";
            $ret = DeployUtils->execmd($cmd);
        }
        else {
            print("ERROR: Copy packages to myWS failed\n");
            $hasError = 1;
            &$execEnded();
        }

        if ( $ret eq 0 ) {
            print("INFO : activate objects success\n");
            unlink("myWS");
        }
        else {
            print("ERROR: Activate objects failed\n");
            $hasHardError = 1;
            &$execEnded();
        }

    }
    else {
        #expect pattern的顺序至关重要，如果要调整这里的match顺序，必须全部场景都要测试，场景包括
        #1）用户密码错误
        #2）主机IP端口错误
        #4）SQL语法错误
        #5）不存在的SQL对象
        #6) sql脚本不存在
        #7）session killed
        #8）执行sql的命令不存在（譬如：sqlplus(oracle)不存在，clpplus(db2)不存在）
        my $logonTimeout = $self->{logonTimeout};
        my $sqlFileName  = $self->{sqlFileName};

        my $hasLogon = 0;
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
            print("Execution start > ");

            if ( $isAutoCommit == 1 ) {
                $spawn->send("\\a ON\n");
                $spawn->expect(
                    undef,
                    [
                        qr/OFF/ => sub {
                            $hasError = 1;
                            $spawn->exp_continue();
                        }
                    ],
                    [
                        qr/ON/ => sub {
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

        $self->{hasLogon} = 1;
        if ( $hasError != 1 and $hasHardError != 1 ) {
            $spawn->send("read $sqlFileName");
            $spawn->expect(
                undef,
                [
                    qr/syntax error/ => sub {
                        print("ERROR: Syntax error.\n");
                        $hasError = 1;
                        $spawn->exp_continue();
                    }
                ],
                [
                    qr/Cannot open/ => sub {
                        print("ERROR: Not such file.\n");
                        $hasError = 1;
                        $spawn->exp_continue();
                    }
                ],
                [
                    qr/cannot/ => sub {
                        print("ERROR");
                        $hasError = 1;
                        $spawn->exp_continue();
                    }
                ],
                [
                    qr/rows affected/ => sub {
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

    $self->{warningCount} = $warningCount;

    return $isFail;
}

1;

