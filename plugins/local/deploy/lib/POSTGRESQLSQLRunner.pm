#!/usr/bin/perl
use strict;

package POSTGRESQLSQLRunner;

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

    my $dbType       = $dbInfo->{dbType};
    my $dbName       = $dbInfo->{sid};
    my $host         = $dbInfo->{host};
    my $port         = $dbInfo->{port};
    my $user         = $dbInfo->{user};
    my $pass         = $dbInfo->{pass};
    my $isAutoCommit = $dbInfo->{autocommit};
    my $dbVersion    = $dbInfo->{version};
    my $dbArgs       = $dbInfo->{args};

    my $self = {};
    bless( $self, $pkg );

    $sqlFile =~ s/^\s*'|'\s*$//g;

    $self->{sqlFileStatus} = $sqlFileStatus;
    $self->{toolsDir}      = $toolsDir;
    $self->{tmpDir}        = $tmpDir;

    $self->{dbType}       = $dbType;
    $self->{host}         = $host;
    $self->{port}         = $port;
    $self->{dbName}       = $dbName;
    $self->{sqlFile}      = $sqlFile;
    $self->{charSet}      = $charSet;
    $self->{user}         = $user;
    $self->{pass}         = $pass;
    $self->{logFilePath}  = $logFilePath;
    $self->{isAutoCommit} = $isAutoCommit;
    $self->{ignoreErrors} = $dbInfo->{ignoreErrors};
    $self->{warningCount} = 0;

    if ( not defined($isInteract) ) {
        $isInteract = 0;
    }
    $self->{isInteract} = $isInteract;

    $self->{PROMPT}   = qr/\n$dbName=> $/s;
    $self->{hasLogon} = 0;

    my $sqlDir      = dirname($sqlFile);
    my $sqlFileName = basename($sqlFile);
    $self->{sqlFileName} = $sqlFileName;

    my $pgHome = "$toolsDir/postgresql-client";
    if ( defined($dbVersion) and -e "$pgHome-$dbVersion" ) {
        $pgHome = "$pgHome-$dbVersion";
    }

    $ENV{LC_MESSAGES}     = 'en_US.UTF-8';
    $ENV{PATH}            = "$pgHome/bin:" . $ENV{PATH};
    $ENV{LD_LIBRARY_PATH} = "$pgHome/lib:" . $ENV{LD_LIBRARY_PATH};

    chdir($sqlDir);

    my $cmd    = "psql -a -h$host -p$port -U$user -d$dbName";
    my $extOpt = "-W -P pager=off -v AUTOCOMMIT=off -v ON_ERROR_ROLLBACK=on -v PROMPT1='%/=> '";

    if ( $isAutoCommit == 1 ) {
        $extOpt = "-W -P pager=off -v AUTOCOMMIT=on -v ON_ERROR_ROLLBACK=on -v PROMPT1='%/=> '";
    }

    print("INFO: $cmd\n");

    my $spawn = Expect->spawn("$cmd $extOpt");

    if ( not defined($spawn) ) {
        die("launch psql client failed, check if it exists and it's permission.\n");
    }

    $spawn->max_accum(2048);

    $self->{spawn} = $spawn;

    return $self;
}

sub test {
    my ($self) = @_;

    my $spawn = $self->{spawn};
    $spawn->log_stdout(0);

    my $PROMPT = $self->{PROMPT};
    my $host   = $self->{host};
    my $port   = $self->{port};
    my $dbName = $self->{dbName};
    my $user   = $self->{user};
    my $pass   = $self->{pass};

    my $hasLogon = 0;

    $spawn->expect(
        undef,
        [
            qr/Password for user $user: $/ => sub {
                $spawn->send("$pass\n");
                $spawn->exp_continue;
            }
        ],
        [
            $PROMPT => sub {
                $hasLogon = 1;
                $spawn->send("\\q\n");
            }
        ],
        [
            eof => sub {

                #print( DeployUtils->convToUTF8( $spawn->before() ) );
            }
        ]
    );

    $spawn->soft_close();

    if ( $hasLogon == 1 ) {
        $self->{hasLogon} = 1;
        print("INFO: postgresql $user\@//$host:$port/$dbName connection test success.\n");
    }
    else {
        print( $spawn->before() );
        print("ERROR: postgresql $user\@//$host:$port/$dbName connection test failed.\n");
    }

    return $hasLogon;
}

sub run {
    my ($self)       = @_;
    my $dbName       = $self->{dbName};
    my $spawn        = $self->{spawn};
    my $logFilePath  = $self->{logFilePath};
    my $charSet      = $self->{charSet};
    my $sqlFile      = $self->{sqlFile};
    my $sqlFileName  = $self->{sqlFileName};
    my $user         = $self->{user};
    my $pass         = $self->{pass};
    my $isAutoCommit = $self->{isAutoCommit};

    my $sqlFile = $sqlFileName;

    my $pipeFile = $logFilePath;
    $pipeFile =~ s/\.log$//;
    $pipeFile = "$pipeFile.run.pipe";

    my $PROMPT = $self->{PROMPT};

    my $hasSendPass    = 0;
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

    my $execEnded = sub {

        #session被kill
        if ( $sessionKilled == 1 ) {
            $spawn->send("\\q\n");
            $isFail = 1;
        }
        elsif ( $hasHardError == 1 ) {
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
                $spawn->send("\\q\n");
                $spawn->soft_close();
            }
            else {
                if ( $self->{isInteract} == 1 ) {
                    my $sqlFileStatus = $self->{sqlFileStatus};
                    $opt = $sqlFileStatus->waitInput( 'Running with error, please select action(commit|rollback)', $pipeFile );
                }

                $opt = 'rollback' if ( not defined($opt) );

                $spawn->send("$opt;\n");

                #$spawn->expect( undef, '-re', $PROMPT );
                $spawn->expect( undef, [ $PROMPT => sub { } ] );
                $spawn->send("\\q\n");
                $spawn->soft_close();

                if ( $opt eq 'rollback' ) {
                    $isFail = 1;
                }
            }
        }
        else {
            $spawn->send("commit;\n");

            #$spawn->expect( undef, '-re', $PROMPT );
            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->send("\\q\n");
            $spawn->soft_close();
        }

        $sqlexecStatus = $spawn->exitstatus();

        #段错误, sqlplus bug
        if ( defined($sqlexecStatus) and $sqlexecStatus != 0 ) {
            print("ERROR: postgresql exit abnormal.\n");

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
        undef,
        [
            qr/Password for user $user: $/ => sub {
                $spawn->send("$pass\n");
                $spawn->exp_continue;
            }
        ],
        [
            $PROMPT => sub {
                $hasLogon = 1;
            }
        ],
        [
            eof => sub {
                $hasHardError = 1;
                $hasError     = 1;
                print( DeployUtils->convToUTF8( $spawn->before() ) );
                &$execEnded();
            }
        ]
    );

    if ( $hasLogon == 1 ) {
        print("Exection start > ");

        $spawn->send("set lc_messages='en_US.UTF-8';\n");
        $spawn->expect( undef, [ $PROMPT => sub { } ] );

        $spawn->send("\\encoding '$charSet'\n");
        $spawn->expect( undef, [ $PROMPT => sub { } ] );

        #$spawn->expect( undef, '-re', $PROMPT );
        $self->{hasLogon} = 1;
        $spawn->send("\\i '$sqlFileName'\n");

        $spawn->expect(
            undef,
            [

                #psql:pgtest.root/2.test.sql:1: ERROR:  syntax error at or near "select1"
                qr/\n(psql:)?($sqlFile:\d+:)?\s*(ERROR|FATAL):\s*(.*?)(?=\n)/ => sub {
                    my $matchContent = DeployUtils->convToUTF8( $spawn->match() );
                    $matchContent =~ /(ERROR|FATAL):(.*?)\s*$/s;
                    $sqlError  = $1;
                    $sqlErrMsg = $2;
                    if ( $charSet ne 'UTF-8' ) {
                        $sqlErrMsg = Encode::encode( "utf-8", Encode::decode( $charSet, $sqlErrMsg ) );
                    }

                    $warningCount = $warningCount + 1;

                    #如果session被kill则自行推出并返回错误
                    if ( $sqlError eq 'FATAL' and $sqlErrMsg =~ /terminating connection/i ) {
                        $sessionKilled = 1;
                    }

                    #如果错误可忽略则输出警告，否则输出错误
                    elsif ( $ignoreErrors =~ /$sqlErrMsg/ ) {
                        $hasWarn = 1;
                    }
                    else {
                        $hasError = 1;
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

