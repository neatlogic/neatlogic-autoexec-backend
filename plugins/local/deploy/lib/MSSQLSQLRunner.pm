#!/usr/bin/perl
use strict;

package MSSQLSQLRunner;
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

    my $dbInfo      = $args{dbInfo};
    my $charSet     = $args{charSet};
    my $logFilePath = $args{logFilePath};
    my $toolsDir    = $args{toolsDir};

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
    $self->{dbName}       = $dbName;
    $self->{hasLogon}     = 0;
    $self->{ignoreErrors} = $dbInfo->{ignoreErrors};
    $self->{warningCount} = 0;

    if ( not defined($isInteract) ) {
        $isInteract = 0;
    }
    $self->{isInteract} = $isInteract;

    $ENV{PATH} = '/opt/mssql-tools/bin:' . $ENV{PATH};

    #mssql 只能运行在UTF-8上
    $ENV{LANG}   = 'en_US.UTF-8';
    $ENV{LC_ALL} = 'en_US.UTF-8';

    my $mssqlHome = "$toolsDir/mssql-client";
    if ( defined($dbVersion) and -e "$mssqlHome-$dbVersion" ) {
        $mssqlHome = "$mssqlHome-$dbVersion";
    }

    $ENV{PATH}            = "$mssqlHome/bin:" . $ENV{PATH};
    $ENV{LD_LIBRARY_PATH} = "$mssqlHome/lib:" . $ENV{LD_LIBRARY_PATH};

    my $sqlDir      = dirname($sqlFile);
    my $sqlFileName = basename($sqlFile);
    $self->{sqlFileName} = $sqlFileName;

    chdir($sqlDir);

    print("INFO: sqlcmd -e -l10 -S $host,$port -U $user -d $dbName\n");

    my $spawn = Expect->spawn("sqlcmd -e -l10 -S $host,$port -U $user -d $dbName");

    if ( not defined($spawn) ) {
        die("launch sqlserver client sqlcmd failed, check if it exists and it's permission.\n");
    }

    $spawn->max_accum(2048);

    $self->{spawn} = $spawn;

    return $self;
}

sub test {
    my ($self) = @_;

    my $PROMPT1 = qr/[\x00]*1> $/;

    my $spawn = $self->{spawn};

    my $host     = $self->{host};
    my $port     = $self->{port};
    my $dbName   = $self->{dbName};
    my $user     = $self->{user};
    my $password = $self->{pass};

    $spawn->log_stdout(0);

    my $hasLogon = 0;

    $spawn->expect(
        undef,
        [
            qr/Password:\s+/is => sub {
                $spawn->send("$password\n");
                $spawn->exp_continue;
            }
        ],
        [
            $PROMPT1 => sub {
                $hasLogon = 1;
                $spawn->send("quit\n");
                $spawn->exp_continue;
            }
        ],
        [
            qr/\x1b\[6n/ => sub {
                $hasLogon = 1;
                $spawn->hard_close();
            }
        ],
        [
            eof => sub {

                #print( DeployUtils->convToUTF8( $spawn->before() ) );
                $spawn->soft_close();
            }
        ]
    );

    if ( $hasLogon == 1 ) {
        $self->{hasLogon} = 1;
        print("INFO: sql server $user\@//$host:$port/$dbName connection test success.\n");
    }
    else {
        print( $spawn->before() );
        print("ERROR: sql server $user\@//$host:$port/$dbName connection test failed.\n");
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

    my $TMPDIR  = $self->{tmpDir};
    my $tmp     = File::Temp->new( DIR => $TMPDIR, SUFFIX => '.sql' );
    my $tmpPath = $tmp->filename;

    if ( $charSet ne 'UTF-8' ) {
        if ( not defined($tmp) ) {
            die("Can not create tmp file in dir $TMPDIR");
        }

        my $orgFH = IO::File->new("<$sqlFileName");
        my $line;

        #mssql client 不支持sql文件编码声明，自己转换为utf8编码
        while ( $line = <$orgFH> ) {
            print $tmp ( Encode::encode( "utf-8", Encode::decode( $charSet, $line ) ) );
        }
        $orgFH->close();
        $tmp->close();
        $sqlFile = $tmpPath;
        $charSet = 'UTF-8';
    }

    my $pipeFile = $logFilePath;
    $pipeFile =~ s/\.log$//;
    $pipeFile = "$pipeFile.run.pipe";

    my $PROMPT1 = qr/\n[\x00]*1> $/is;
    my $PROMPT2 = qr/\n[\x00]*2> $/is;
    my $PROMPT  = qr/\n[\x00]*\d+> $/is;

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
    my $errMsg = "\n";

    my $execEnded = sub {

        #session被kill
        if ( $hasHardError == 1 or $sessionKilled == 1 ) {
            $isFail = 1;
        }

        #ORA 错误
        elsif ( $hasError == 1 ) {
            print($errMsg) if ( $errMsg ne "\n" );

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

                $opt = uc($opt);
                $spawn->send("$opt TRANSACTION;\n");
                $spawn->expect( undef, [ $PROMPT2 => sub { } ] );
                $spawn->send("go\n");
                $spawn->expect( undef, [ $PROMPT1 => sub { } ] );
                $spawn->send("quit\n");
                $spawn->soft_close();

                if ( $opt eq 'rollback' ) {
                    $isFail = 1;
                }
            }
        }
        else {
            if ( not $isAutoCommit == 1 ) {
                $spawn->send("COMMIT TRANSACTION;\n");
                $spawn->expect( undef, [ $PROMPT2 => sub { } ] );
                $spawn->send("go\n");
                $spawn->expect( undef, [ $PROMPT1 => sub { } ] );
            }

            $spawn->send("quit\n");
            $spawn->soft_close();
        }

        $sqlexecStatus = $spawn->exitstatus();

        #段错误, sqlplus bug
        if ( defined($sqlexecStatus) and $sqlexecStatus != 0 ) {
            print("ERROR: sqlcmd exit abnormal.\n");

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

            #Msg 911, Level 16, State 1, Server DESKTOP-3QFCLMR, Line 1
            #数据库 'test2' 不存在。请确保正确地输入了该名称。
            #Msg 208, Level 16, State 1, Server DESKTOP-3QFCLMR, Line 4
            #对象名 'test12' 无效。
            qr/(?<=\n)Msg\s+\d+,\s+Level\s+\d+,\s+State\s+\d+,[^\n]+\n[^\n]+(?=\n)/ => sub {
                my $matchContent = $spawn->match();
                my $nwPos = index( $matchContent, "\n" );
                $sqlError = substr( $matchContent, 0, $nwPos - 1 );
                $sqlErrMsg = substr( $matchContent, $nwPos + 1 );

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
                    $hasError = 1;
                }

                #$spawn->exp_continue;
            }
        ],
        [

            #Sqlcmd: Error: Microsoft ODBC Driver 13 for SQL Server : 用户 'linuxtest' 登录失败。.
            qr/(?<=\n)Sqlcmd:\s+Error:\s+[^\n]+(?<=\n)/ => sub {
                $sqlErrMsg    = $spawn->match();
                $hasHardError = 1;

                #$spawn->exp_continue;
            }
        ],
        [

            #TCP Provider: Error code 0x68
            qr/(?<=\n)TCP\s+Provider:\s+Error\s+code\s+[^\n]+(?<=\n)/ => sub {
                $sqlErrMsg    = $spawn->match();
                $hasHardError = 1;

                #$spawn->exp_continue;
            }
        ],
        [
            qr/Password:\s+/is => sub {
                $spawn->send("$password\n");
                $hasSendPassword = 1;
                $spawn->exp_continue;
            }
        ],
        [
            $PROMPT1 => sub {
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
        $self->{hasLogon} = 1;
        print("Exection start > ");

        #$spawn->send("BEGIN TRANSACTION\n");
        if ( $isAutoCommit == 1 ) {
            $spawn->send("SET IMPLICIT_TRANSACTIONS OFF;\n");
        }
        else {
            $spawn->send("SET IMPLICIT_TRANSACTIONS ON;\n");
        }

        $spawn->expect( undef, '-re', $PROMPT2 );
        $spawn->send("go\n");
        $spawn->expect( undef, '-re', $PROMPT1 );
        $spawn->send(":r $sqlFile\n");

        #$spawn->expect( undef, '-re', $PROMPT2 );
        #$spawn->send("go\n");

        $spawn->expect(
            undef,
            [

                #Msg 911, Level 16, State 1, Server DESKTOP-3QFCLMR, Line 1
                #数据库 'test2' 不存在。请确保正确地输入了该名称。
                #Msg 208, Level 16, State 1, Server DESKTOP-3QFCLMR, Line 4
                #对象名 'test12' 无效。
                qr/\nMsg\s+\d+,\s+Level\s+\d+,\s+State\s+\d+,[^\n]+\n[^\n]+(?=\n)/ => sub {
                    my $matchContent = $spawn->match();
                    my $nwPos = index( $matchContent, "\r\n" );
                    $sqlError = substr( $matchContent, 0, $nwPos - 1 );
                    $sqlErrMsg = substr( $matchContent, $nwPos + 1 );

                    $warningCount = $warningCount + 1;

                    #如果session被kill则自行退出并返回错误
                    if ( $sqlError =~ /ERROR 2013 \(HY000\)/i ) {
                        $hasHardError  = 1;
                        $sessionKilled = 1;
                    }

                    #如果错误可忽略则输出警告，否则输出错误
                    elsif ( $ignoreErrors =~ /$sqlError/ ) {
                        $hasWarn = 1;
                        print("\nWARNNING: $sqlError:$sqlErrMsg\n");
                    }
                    else {
                        $hasError = 1;
                        print("\nERROR: $sqlError:$sqlErrMsg\n");
                    }
                    $spawn->exp_continue;
                }
            ],
            [
                $PROMPT1 => sub {
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

