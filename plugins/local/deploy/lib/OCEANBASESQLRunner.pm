#!/usr/bin/perl
use strict;

package OCEANBASESQLRunner;

use FindBin;
use Expect;
use DeployUtils;
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
    $self->{hasLogon}     = 0;
    $self->{ignoreErrros} = $dbInfo->{ignoreErrors};
    $self->{warningCount} = 0;
    $self->{logonTimeout} = $dbInfo->{logonTimeout};

    #$self->{PROMPT} = qr/(obclient)>\s$/;
    $self->{PROMPT} = qr/obclient(\s+\[$dbName\])?>\s$/;

    if ( not defined($isInteract) ) {
        $isInteract = 0;
    }
    $self->{isInteract} = $isInteract;

    if ( defined($sqlFile) and $sqlFile ne '' and $sqlFile ne 'test' ) {
        my $sqlDir      = dirname($sqlFile);
        my $sqlFileName = basename($sqlFile);
        $self->{sqlFileName} = $sqlFileName;
        chdir($sqlDir);
    }

    my $obHome = "$toolsDir/ob-client";
    if ( defined($dbVersion) and -e "$obHome-$dbVersion" ) {
        $obHome = "$obHome-$dbVersion";
    }

    $ENV{PATH} = "$obHome/bin:" . $ENV{PATH};

    $ENV{MYSQL_HISTFILE} = '/dev/null';

    print(qq{INFO: Obclient -vs -h$host -P$port -u"$user" -p"******" -A -D"$dbName"\n});

    my $spawn = Expect->spawn(qq{obclient -vs -h$host -P$port -u"$user" -p"$pass" -A -D"$dbName"});

    if ( not defined($spawn) ) {
        die("launch obclient failed, check if it exists and it's permission.\n");
    }

    $spawn->max_accum(2048);

    $self->{spawn} = $spawn;

    return $self;
}

sub test {
    my ($self) = @_;

    my $spawn = $self->{spawn};
    $spawn->log_stdout(0);

    my $dbType       = $self->{dbType};
    my $host         = $self->{host};
    my $port         = $self->{port};
    my $user         = $self->{user};
    my $dbName       = $self->{dbName};
    my $logonTimeout = $self->{logonTimeout};
    my $PROMPT       = $self->{PROMPT};

    my $hasHardError = 0;
    my $hasLogon     = 0;

    $spawn->expect(
        $logonTimeout,
        [
            $PROMPT => sub {
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
        print("INFO: Obclient $user\@//$host:$port/$dbName connection test success.\n");
    }
    else {
        my $errMsg = DeployUtils->convToUTF8( $spawn->before() );
        print($errMsg );
        print("ERROR: Obclient $user\@//$host:$port/$dbName connection test failed.\n");
    }

    return $hasLogon;
}

sub run {
    my ($self)       = @_;
    my $spawn        = $self->{spawn};
    my $dbName       = $self->{dbName};
    my $logFilePath  = $self->{logFilePath};
    my $charSet      = $self->{charSet};
    my $sqlFile      = $self->{sqlFile};
    my $sqlFileName  = $self->{sqlFileName};
    my $isAutoCommit = $self->{isAutoCommit};
    my $PROMPT       = $self->{PROMPT};

    my $pipeFile = $logFilePath;
    $pipeFile =~ s/\.log$//;
    $pipeFile = "$pipeFile.run.pipe";

    my $hasSendAutocommit = 0;
    my $hasSendCharset    = 0;
    my $hasSendSql        = 0;
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

            print("\nERROR: Some error occurred, check the log for detail.\n");

            my $opt;
            if ( $isAutoCommit == 1 ) {
                print("\nWARN: Autocommit is on, select 'ignore' to continue, 'abort' to abort the job.\n");
                if ( $self->{isInteract} == 1 ) {
                    my $sqlFileStatus = $self->{sqlFileStatus};
                    $opt = $sqlFileStatus->waitInput( 'Execute failed, select action(ignore|abort)', $pipeFile );
                }

                $opt = 'abort' if ( not defined($opt) );

                if ( $opt eq 'abort' ) {
                    $isFail = 1;
                }
                $spawn->send("exit;\n");
                $spawn->soft_close();
            }
            else {

                if ( $self->{isInteract} == 1 ) {
                    my $sqlFileStatus = $self->{sqlFileStatus};
                    $opt = $sqlFileStatus->waitInput( 'Running with error, please select action(commit|rollback)', $pipeFile );
                }

                $opt = 'rollback' if ( not defined($opt) );

                $spawn->send("$opt;\n");
                $spawn->expect( undef, [ $PROMPT => sub { } ] );
                $spawn->send("exit;\n");
                $spawn->soft_close();

                if ( $opt eq 'rollback' ) {
                    $isFail = 1;
                }
            }
        }
        else {
            $spawn->send("commit;\n");
            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->send("exit;\n");
            $spawn->soft_close();
        }

        $sqlexecStatus = $spawn->exitstatus();

        #段错误, sqlplus bug
        if ( defined($sqlexecStatus) and $sqlexecStatus != 0 ) {
            print("ERROR: Obclient exit abnormal.\n");

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
            $PROMPT => sub {
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
            $spawn->send("SET autocommit=1;\n");
        }
        else {
            $spawn->send("SET autocommit=0;\n");
        }

        $spawn->expect( undef, [ $PROMPT => sub { } ] );

        my $sqlEncoding = $charSet;
        $sqlEncoding = 'UTF8' if ( $charSet eq 'UTF-8' );
        $spawn->send("SET NAMES '$sqlEncoding';\n");
        $spawn->expect( undef, [ $PROMPT => sub { } ] );

        $self->{hasLogon} = 1;
        $spawn->send("source $sqlFileName;\n");
        $spawn->expect(
            undef,
            [

                #ERROR 1146 (42S02): Table 'test.dual1' doesn't exist
                qr/(?<=\n)ERROR\s*[^:]*?:.*?(?=\n)|(?<=\n)ERROR.*?:.*?\n.*?(?=\n)/ => sub {
                    my $matchContent = $spawn->match();
                    $matchContent =~ /^(ERROR\s*[^:]*?):\s*(.*?)\s*$/s;
                    $sqlError     = $1;
                    $sqlErrMsg    = $2;
                    $warningCount = $warningCount + 1;

                    #如果session被kill则自行退出并返回错误
                    if ( $sqlError =~ /ERROR 2013 \(HY000\)/i ) {
                        $hasHardError  = 1;
                        $sessionKilled = 1;
                    }

                    #如果错误可忽略则输出警告，否则输出错误
                    elsif ( $ignoreErrors =~ /$sqlError/ ) {
                        $hasWarn = 1;
                    }
                    else {
                        $hasError     = 1;
                        $matchContent = DeployUtils->convToUTF8($matchContent);
                        print("ERROR: $matchContent\n");
                    }
                    $spawn->exp_continue;
                }
            ],
            [
                $PROMPT => sub {
                    &$execEnded();
                }
            ],
            [ eof => sub { &$execEnded(); } ]
        );
    }

    $self->{warningCount} = $warningCount;

    return $isFail;
}

1;
