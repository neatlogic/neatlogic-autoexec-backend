#!/usr/bin/perl
use strict;

package INFORMIXSQLRunner;

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

    my $self = {};
    bless( $self, $pkg );

    $sqlFile =~ s/^\s*'|'\s*$//g;

    $self->{sqlFileStatus} = $sqlFileStatus;
    $self->{toolsDir}      = $toolsDir;
    $self->{tmpDir}        = $tmpDir;

    $self->{PROMPT}       = qr/\n>\s/is;
    $self->{dbType}       = $dbType;
    $self->{host}         = $host;
    $self->{port}         = $port;
    $self->{sqlFile}      = $sqlFile;
    $self->{charSet}      = $charSet;
    $self->{user}         = $user;
    $self->{pass}         = $pass;
    $self->{dbName}       = $dbName;
    $self->{logFilePath}  = $logFilePath;
    $self->{isAutoCommit} = $isAutoCommit;
    $self->{hasLogon}     = 0;
    $self->{ignoreErrors} = $dbInfo->{ignoreErrors};
    $self->{warningCount} = 0;

    if ( not defined($isInteract) ) {
        $isInteract = 0;
    }
    $self->{isInteract} = $isInteract;

    if ( not defined($dbServerLocale) ) {
        $self->{hasError} = 1;
        print("ERROR: informix database server locale not set in config, config example:<dbalias>.locale=zh_CN.utf8.\n");
    }

    my $serverName;
    if ( $dbName =~ /([^\@]+)\@([^\@]+)/ ) {
        $serverName = $2;
    }
    else {
        $self->{hasError} = 1;
        print("ERROR: informix database name:$dbName, malform format, example:dbname\@servername\n");
    }

    #export INFORMIXDIR=/app/ezdeploy/tools/informix-client
    #export INFORMIXSQLHOSTS=/app/ezdeploy/tools/informix-client/etc/sqlhosts.test
    #export INFORMIXSERVER=ol_informix1210
    #export INFORMIXSERVER=test
    #export GL_USEGLU=1
    #export CLIENT_LOCALE=zh_CN.utf8
##export CLIENT_LOCALE=zh_CN.gb
    #
##export SERVER_LOCALE=zh_CN.utf8
    #export DB_LOCALE=zh_CN.utf8
##export SERVER_LOCALE=zh_CN.gb
##export DB_LOCALE=zh_CN.gb
    #
    $ENV{INFORMIXSERVER} = $serverName;
    $ENV{GL_USEGLU}      = 1;
    $ENV{DB_LOCALE}      = $dbServerLocale;

    if ( $dbServerLocale =~ /\.819/ or $dbServerLocale =~ /\.8859-1/ ) {
        $ENV{CLIENT_LOCALE} = 'en_US.819';
        $ENV{LANG}          = 'en_US.UTF8';
    }
    else {
        if ( $charSet eq 'UTF-8' ) {
            $ENV{CLIENT_LOCALE} = 'zh_CN.utf8';
            $ENV{LANG}          = 'en_US.UTF8';
        }
        else {
            $ENV{CLIENT_LOCALE} = 'zh_CN.gb';
            $ENV{LANG}          = 'en_US.GBK';
        }
    }

    my $informixHome = "$toolsDir/informix-client";
    if ( defined($dbVersion) and -e "$informixHome-$dbVersion" ) {
        $informixHome = "$informixHome-$dbVersion";
    }

    $ENV{INFORMIXDIR} = $informixHome;
    $ENV{PATH}        = "$informixHome/bin:" . $ENV{PATH};

    my $sqlDir      = dirname($sqlFile);
    my $sqlFileName = basename($sqlFile);
    $self->{sqlFileName} = $sqlFileName;

    my $tmp = File::Temp->new( DIR => $tmpDir, UNLINK => 1, SUFFIX => '.informix' );
    my $content = "$serverName onsoctcp $host $port\n";
    print $tmp ($content);
    my $sqlHostFile = $tmp->filename;
    $tmp->flush();
    $self->{INFORMIX_SQLHOST_TMP} = $tmp;
    $ENV{INFORMIXSQLHOSTS} = $sqlHostFile;

    chdir($sqlDir);

    print("INFO: dbaccess - - #connect to '$dbName' user '$user'\n");

    my $spawn = Expect->spawn("dbaccess - -\n");

    #sleep(20);
    #$spawn->debug(1);

    if ( not defined($spawn) ) {
        die("launch informix client dbaccess failed, check if it exists and it's permission.\n");
    }

    $spawn->max_accum(2048);

    $self->{spawn} = $spawn;

    return $self;
}

sub test {
    my ($self) = @_;

    my $host     = $self->{host};
    my $port     = $self->{port};
    my $user     = $self->{user};
    my $password = $self->{pass};
    my $dbName   = $self->{dbName};

    my $PROMPT = $self->{PROMPT};

    my $spawn = $self->{spawn};
    $spawn->log_stdout(0);

    $spawn->expect( 3, [ qr/> $/is => sub { } ] );
    $spawn->send("connect to '$dbName' user '$user';\n");
    $spawn->expect( 3, [ qr/PASSWORD:/is => sub { } ] );
    $spawn->send("$password\n");

    my $hasLogon = 0;

    $spawn->expect(
        10,
        [

            #  951: Incorrect password or user wenhb1@sit_deploy_24 is not known on the database server.
            #Error in line 1
            #Near character position 1
            qr/(?<=\n)\s*?\d+:.*?\nError in line \d+\s*\nNear character position \d+\s*\n/is => sub {
                print( $spawn->before() );
                print( $spawn->match() );
                print( $spawn->after() );
            }
        ],
        [
            "Connected." => sub {
                $hasLogon = 1;
                $spawn->send("\cd");
            }
        ],
        [
            $PROMPT => sub {
                $hasLogon = 1;
                $spawn->send("\cd");
            }
        ],
        [
            timeout => sub {
                print("ERROR: connection timeout.\n");
                $spawn->send("\cc");
                $hasLogon = 0;
            }
        ],
        [
            eof => sub {
                $hasLogon = 0;

                #print( DeployUtils->convToUTF8( $spawn->before() ) );
            }
        ]
    );

    $spawn->soft_close();

    if ( $hasLogon == 1 ) {
        $self->{hasLogon} = 1;
        print("INFO: informix $user\@//$host:$port/$dbName connection test success.\n");
    }
    else {
        print( $spawn->before() );
        print("ERROR: informix $user\@//$host:$port/$dbName connection test failed.\n");
    }

    return $hasLogon;
}

sub run {
    my ($self)      = @_;
    my $password    = $self->{pass};
    my $spawn       = $self->{spawn};
    my $logFilePath = $self->{logFilePath};
    my $charSet     = $self->{charSet};
    my $sqlFile     = $self->{sqlFile};
    my $sqlFileName = $self->{sqlFileName};
    my $user        = $self->{user};
    my $dbName      = $self->{dbName};
    my $sqlFile     = $sqlFileName;

    my $pipeFile = $logFilePath;
    $pipeFile =~ s/\.log$//;
    $pipeFile = "$pipeFile.run.pipe";

    #my $PROMPT = qr/\n>\s/is;
    my $PROMPT = $self->{PROMPT};

    my $hasSendSql = 0;
    my ( $sqlError, $sqlErrMsg );
    my $hasWarn       = 0;
    my $hasError      = 0;
    my $hasHardError  = 0;
    my $sqlexecStatus = 0;
    my $warningCount  = 0;

    my $ignoreErrors = $self->{ignoreErrors};

    my $isFail = 0;

    my $execEnded = sub {

        #session被kill
        if ( $hasHardError == 1 ) {
            $isFail = 1;
        }

        #ORA 错误
        elsif ( $hasError == 1 ) {
            print("\nERROR: some error occurred, check the log for detail.\n");

            my $opt;
            if ( $self->{isInteract} == 1 ) {
                my $sqlFileStatus = $self->{sqlFileStatus};
                $opt = $sqlFileStatus->waitInput( 'Running with error, please select action(commit|rollback)', $pipeFile );
            }

            $opt = 'rollback' if ( not defined($opt) );

            $spawn->send("$opt;\n");
            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->send("\cd");
            $spawn->expect(undef);

            if ( $opt eq 'rollback' ) {
                $isFail = 1;
            }
        }
        else {
            $spawn->send("commit;\n");
            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->send("\cd\cd");
            $spawn->expect(undef);
        }

        $sqlexecStatus = $spawn->exitstatus();

        #段错误, sqlplus bug
        if ( not defined($sqlexecStatus) or $sqlexecStatus != 0 ) {
            print("ERROR: dbaccess exit abnormal.\n");

            $isFail = 1;
        }
    };

    if ( $self->{hasError} != 1 ) {

        #expect pattern的顺序至关重要，如果要调整这里的match顺序，必须全部场景都要测试，场景包括
        #1）用户密码错误
        #2）主机IP端口错误
        #3）DB名称错误
        #4）SQL语法错误
        #5）不存在的SQL对象
        #6) sql脚本不存在
        #7）session killed
        #8）执行sql的命令不存在（譬如：sqlplus(oracle)不存在，clpplus(db2)不存在）

        $spawn->expect( 3, [ qr/> $/is => sub { } ] );
        $spawn->send("connect to '$dbName' user '$user';\n");
        $spawn->expect( 3, [ qr/PASSWORD:/is => sub { } ] );
        $spawn->send("$password\n");

        $spawn->expect(
            undef,
            [

                #  951: Incorrect password or user wenhb1@sit_deploy_24 is not known on the database server.
                #Error in line 1
                #Near character position 1
                qr/(?<=\n)\s*?\d+:.*?\nError in line \d+\s*\nNear character position \d+\s*\n/is => sub {
                    my $matchContent = $spawn->match();
                    $matchContent =~ s/^\s+//s;
                    my $nwPos = index( $matchContent, "\n" );
                    $sqlError = substr( $matchContent, 0, $nwPos - 1 );
                    $sqlErrMsg = $sqlError;

                    if ( $charSet ne 'UTF-8' ) {
                        $sqlErrMsg = Encode::encode( "utf-8", Encode::decode( $charSet, $sqlErrMsg ) );
                    }

                    #dbName错误
                    if ( index( $sqlError, '329: Database not found or no system permission' ) >= 0 ) {
                        $hasHardError = 1;
                    }
                    elsif ( index( $sqlError, '951: Incorrect password or user' ) >= 0 ) {
                        $hasHardError = 1;
                    }
                    elsif ( index( $sqlError, '908: Attempt to connect to database server' ) >= 0 ) {
                        $hasHardError = 1;
                    }

                    #如果错误可忽略则输出警告，否则输出错误
                    if ( $ignoreErrors =~ /$sqlError/ ) {
                        $hasWarn = 1;
                    }
                    else {
                        $matchContent = DeployUtils->convToUTF8($matchContent);
                        print("ERROR: $matchContent\n");
                        $hasError = 1;
                    }

                    #$spawn->exp_continue;
                    &$execEnded();
                }
            ],
            [
                $PROMPT => sub {
                    if ( $hasError == 0 and $hasSendSql == 0 ) {
                        $self->{hasLogon} = 1;
                        print("Exection start > ");

                        $spawn->send("begin work;\n");
                        $spawn->expect( undef, [ $PROMPT => sub { } ] );
                        $hasSendSql = 1;

                        my $fh = IO::File->new("<$sqlFile");
                        if ( not defined($fh) ) {
                            $hasHardError = 1;
                            print("ERROR: open file $sqlFile failed, file not exists or permission denied.\n");
                        }
                        else {
                            my ( $line, $expContent );
                            while ( $line = <$fh> ) {
                                $spawn->send($line);
                                $spawn->expect( undef, [ $PROMPT => sub { } ] );
                                $expContent = DeployUtils->convToUTF8( $spawn->before() );
                                if ( $expContent =~ /\s*(\d+:.*?)\nError in line \d+\s*\nNear character position \d+\s*/is ) {
                                    $warningCount = $warningCount + 1;
                                    $sqlError     = $1;
                                    $sqlErrMsg    = $sqlError;

                                    #如果错误可忽略则输出警告，否则输出错误
                                    if ( $ignoreErrors =~ /$sqlError/ ) {
                                        $hasWarn = 1;
                                    }
                                    else {
                                        print("ERROR: $expContent\n");
                                        $hasError = 1;
                                    }
                                }

                            }
                            &$execEnded();

                            #$spawn->exp_continue;
                        }
                    }
                    else {
                        &$execEnded();
                    }

                }
            ],
            [
                eof => sub {

                    #$sqlErrMsg = $spawn->before();

                    #IP or Port error
                    #CT-LIBRARY error:
                    #        ct_connect(): network packet layer: internal net library error: Net-Lib protocol driver call to connect two endpoints failed
                    #Session Killed
                    #CT-LIBRARY error:
                    #        ct_results(): network packet layer: internal net library error: Net-Library operation terminated due to disconnect
                    #$hasHardError = 1 if ( $sqlErrMsg =~ /\s*\d+:.*?\nError in line \d+\s*\nNear character position \d+\s*\n/is );
                    #if ( $charSet ne 'UTF-8' ) {
                    #    $sqlErrMsg = Encode::encode( "utf-8", Encode::decode( $charSet, $sqlErrMsg ) );
                    #}
                    #$sqlErrMsg =~ s/\r|\n/ /g;
                    $hasHardError = 1;
                    $hasError     = 1;
                    print( DeployUtils->convToUTF8( $spawn->before() ) );
                    &$execEnded();
                }
            ]
        );
    }
    else {
        &$execEnded();
    }

    $self->{warningCount} = $warningCount;

    return $isFail;
}

1;

