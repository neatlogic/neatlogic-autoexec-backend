#!/usr/bin/perl
use strict;

package ORACLESQLRunner;

use FindBin;
use Expect;
use Encode;
use File::Basename;
use File::Temp;
use Cwd;
use Expect;

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
    my $addrs          = $dbInfo->{addrs};
    my $addrsCount     = scalar(@$addrs);
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

    my $oraClientDir = 'oracle-client';
    if ( defined($dbVersion) and -e "$toolsDir/oracle-client-$dbVersion" ) {
        $oraClientDir = "oracle-client-$dbVersion";
    }

    $ENV{ORACLE_HOME}     = "$toolsDir/$oraClientDir";
    $ENV{LD_LIBRARY_PATH} = $ENV{ORACLE_HOME} . '/lib:' . $ENV{ORACLE_HOME} . '/bin' . $ENV{LD_LIBRARY_PATH};
    $ENV{PATH}            = "$toolsDir/$oraClientDir/bin:$toolsDir/oracle-sqlcl/bin:" . $ENV{PATH};

    if ( defined($dbServerLocale) and ( $dbServerLocale eq 'ISO-8859-1' or $dbServerLocale =~ /\.WE8ISO8859P1/ ) ) {
        $ENV{NLS_LANG} = 'AMERICAN_AMERICA.WE8ISO8859P1';
        print("INFO: Set NLS_LANG to $ENV{NLS_LANG} while db server locale is set.\n");
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
    $self->{addrs}        = $addrs;
    $self->{addrsCount}   = $addrsCount;
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
    $self->{ignoreErros}  = $dbInfo->{ignoreErrors};
    $self->{warningCount} = 0;

    if ( not defined($isInteract) ) {
        $isInteract = 0;
    }
    $self->{isInteract} = $isInteract;

    my $sqlRunner = 'sqlplus';
    if ( -f "$toolsDir/oracle-sqlcl/bin/sql" ) {
        $sqlRunner = "sql";
    }

    $self->{sqlRunner} = $sqlRunner;

    if ( $sqlRunner eq 'sqlplus' ) {
        $self->{PROMPT} = qr/\nSQL> $/s;
    }
    else {
        $self->{PROMPT} = qr/\x1b\[2K\rSQL> \x1b\[m/s;    #
    }

    $self->{hasLogon} = 0;

    if ( $addrsCount > 1 ) {
        my $TMPDIR = $self->{tmpDir};
        my $tmp    = File::Temp->newdir( "oratns-XXXXX", DIR => $TMPDIR, UNLINK => 1 );
        my $tnsDir = $tmp->dirname();
        $ENV{TNS_ADMIN} = $tnsDir;
        my $fh = IO::File->new(">$tnsDir/tnsnames.ora");
        if ( defined($fh) ) {
            my $tnsEntry = "orcl=" . $self->getTnsDesc() . "\n";
            if ( print $fh ($tnsEntry) ) {
                print("INFO: use tns entry: $tnsEntry\n");
            }
            else {
                die("ERROR: write tns entry to file $tnsDir/tnsnames.ora failed, $!\n");
            }
            $self->{TNSNAMES_TMPDIR} = $tmp;
            $fh->close();
        }
        else {
            die("ERROR: create file $tnsDir/tnsnames.ora failed, $!\n");
        }
    }

    $ENV{TERM} = 'vt100';
    my $spawn;

    my $sqlDir      = dirname($sqlFile);
    my $sqlFileName = basename($sqlFile);
    $self->{sqlDir}      = $sqlDir;
    $self->{sqlFileName} = $sqlFileName;

    chdir($sqlDir);

    if ( $sqlFile =~ /\.ctl/i ) {
        $ENV{LANG}     = 'en_US.ISO-8859-1';
        $ENV{LC_ALL}   = 'en_US.ISO-8859-1';
        $ENV{NLS_LANG} = 'AMERICAN_AMERICA.WE8ISO8859P1';

        $self->{fileType} = 'CTL';

        #my $sqlFileName = basename($sqlFile);
        if ( $addrsCount == 1 ) {
            print("INFO: sqlldr userid=$user/******\@//$host:$port/$dbName $dbArgs control='$sqlFileName'\n");
            $spawn = Expect->spawn("sqlldr userid='$user/\"$pass\"'\@//$host:$port/$dbName $dbArgs control='$sqlFileName'");
        }
        else {
            print("INFO: sqlldr userid=$user/******\@orcl $dbArgs control='$sqlFileName'\n");
            $spawn = Expect->spawn("sqlldr userid='$user/\"$pass\"'\@orcl $dbArgs control='$sqlFileName'");
        }
    }
    elsif ( $sqlFile =~ /\.dmp/i ) {
        $ENV{LANG}     = 'en_US.ISO-8859-1';
        $ENV{LC_ALL}   = 'en_US.ISO-8859-1';
        $ENV{NLS_LANG} = 'AMERICAN_AMERICA.WE8ISO8859P1';

        $self->{fileType} = 'DMP';

        # oracle import
        if ( $addrsCount == 1 ) {
            print("INFO: imp $user/******\@//$host:$port/$dbName $dbArgs file=$sqlFileName\n");
            $spawn = Expect->spawn("imp '$user/\"$pass\"'\@//$host:$port/$dbName $dbArgs file='$sqlFileName'");
        }
        else {
            print("INFO: imp $user/******\@orcl $dbArgs file=$sqlFileName\n");
            $spawn = Expect->spawn("imp '$user/\"$pass\"'\@orcl $dbArgs file='$sqlFileName'");
        }
    }
    else {
        $self->{fileType} = 'SQL';

        if ( $addrsCount == 1 ) {
            print("INFO: $sqlRunner -R 1 -L $user/******\@//$host:$port/$dbName \@$sqlFileName\n");

            #print( "$sqlRunner -R 1 -L '$user/\"$pass\"'\@//$host:$port/$dbName", "\n" );
            $spawn = Expect->spawn("$sqlRunner -R 1 -L '$user/\"$pass\"'\@//$host:$port/$dbName");
        }
        else {
            print("INFO: $sqlRunner -R 1 -L $user/******\@orcl \@$sqlFileName\n");
            $spawn = Expect->spawn("$sqlRunner -R 1 -L '$user/\"$pass\"'\@orcl");
        }
    }

    if ( not defined($spawn) ) {
        die("launch oracle client failed, check if it exists and it's permission.\n");
    }

    #$spawn->slave->stty(qw(raw -echo));
    $spawn->max_accum(2048);
    $self->{spawn} = $spawn;

    return $self;
}

sub getTnsDesc {
    my ($self)    = @_;
    my $sid       = $self->{dbName};
    my $addrs     = $self->{addrs};
    my $addrsDesc = '';

    foreach my $aAddr (@$addrs) {

        #(ADDRESS=(PROTOCOL=TCP)(HOST=10.4.80.64)(PORT=1521))
        $addrsDesc = $addrsDesc . "(ADDRESS=(PROTOCOL=TCP)(HOST=$aAddr->{host})(PORT=$aAddr->{port}))";
    }

    #(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=10.4.80.63)(PORT=1521))(ADDRESS=(PROTOCOL=TCP)(HOST=10.4.80.64)(PORT=1521))(LOAD_BALANCE=yes)(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=dzdb)))
    my $tnsDesc = "(DESCRIPTION=$addrsDesc(LOAD_BALANCE=yes)(CONNECT_DATA=(SERVER=DEDICATED)(SERVICE_NAME=$sid)))";

    return $tnsDesc;
}

sub test {
    my ($self) = @_;

    my $hasLogon = 0;

    my $spawn  = $self->{spawn};
    my $PROMPT = $self->{PROMPT};
    my $host   = $self->{host};
    my $port   = $self->{port};
    my $dbName = $self->{dbName};
    my $user   = $self->{user};

    $spawn->log_stdout(0);

    $spawn->expect(
        undef,
        [
            qr/(?<=\n)Usage(\s*\d*):\s*SQLPLUS.*?(?=\n)/i => sub {
                $spawn->send("\cC\cC\n");
                print( $spawn->before() );
                print( $spawn->match() );
                print( $spawn->after() );
            }
        ],
        [
            qr/ORA-28001/i => sub {
                $spawn->send("\cC\cC\n");
                print( $spawn->before() );
                print( $spawn->match() );
                print( $spawn->after() );
            }
        ],
        [
            $PROMPT => sub {
                $hasLogon = 1;
                $spawn->send("exit;\n");
            }
        ],
        [
            eof => sub {

                #print( DeployUtils->convToUTF8( $spawn->before() ) );
            }
        ]
    );

    $spawn->hard_close();

    if ( $hasLogon == 1 ) {
        $self->{hasLogon} = 1;
        print("INFO: oracle $user\@//$host:$port/$dbName connection test success.\n");
    }
    else {
        print( $spawn->before() );
        print("ERROR: oracle $user\@//$host:$port/$dbName connection test failed.\n");
    }

    return $hasLogon;
}

sub run {
    my ($self)       = @_;
    my $spawn        = $self->{spawn};
    my $logFilePath  = $self->{logFilePath};
    my $charSet      = $self->{charSet};
    my $sqlRunner    = $self->{sqlRunner};
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

    my $sqlEndHandle = sub {

        #session被kill
        if ( $hasHardError == 1 or $sessionKilled == 1 ) {
            $isFail = 1;
        }

        #ORA 错误
        elsif ( $hasError == 1 || $hasWarn == 1 ) {
            $spawn->send("show err\n");
            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->clear_accum();

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
                $spawn->send(" exit;\n");
                $spawn->expect(undef);
            }
            else {
                if ( $self->{isInteract} == 1 ) {
                    my $sqlFileStatus = $self->{sqlFileStatus};
                    $opt = $sqlFileStatus->waitInput( 'Running with error, please select action(commit|rollback)', $pipeFile );
                }

                $opt = 'rollback' if ( not defined($opt) );

                $spawn->send(" $opt;\n");
                $spawn->expect( undef, [ $PROMPT => sub { } ] );
                $spawn->clear_accum();

                $spawn->send(" exit;\n");
                $spawn->expect(undef);

                if ( $opt eq 'rollback' ) {
                    $isFail = 1;
                }
            }
        }
        else {
            $spawn->send(" commit;\n");
            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->clear_accum();

            $spawn->send(" exit;\n");
            $spawn->expect(undef);
        }

        $sqlplusStatus = $spawn->exitstatus();

        #段错误, sqlplus bug
        if ( defined($sqlplusStatus) and $sqlplusStatus != 0 ) {
            print("ERROR: sqlplus exit abnormal.");
            $isFail = 1;
        }
    };

    if ( $fileType eq 'CTL' ) {
        $spawn->expect(undef);
        if ( $spawn->exitstatus() ne 0 ) {
            $hasError = 1;
            $isFail   = 1;
            print("ERROR: sqlldr failed.\n");
        }

    }
    elsif ( $fileType eq 'DMP' ) {
        my $tabExist = 0;
        $spawn->expect(
            undef,
            [

                #EXP-00056: ORACLE error 1017 encountered
                #ORA-01017: invalid username/password; logon denied
                qr/invalid username\/password; logon deniedUsername:/ => sub {
                    $isFail = 1;
                    $spawn->send("\cd\n");
                    print("\nERROR: username/password incorrect.\n");
                }
            ],
            [

                #IMP-00002: failed to open zy.dbuser/test.dmp for read
                #Import file: expdat.dmp >
                qr/(?<=\n)Import\s+file.*?\>/ => sub {
                    $isFail = 1;
                    $spawn->send("\cd\n");
                    print("\nERROR: open file $sqlFile failed, this file exist? has permission?\n");
                }
            ],
            [

                #EXP-00056: ORACLE error 12154 encountered
                #ORA-12154: TNS:could not resolve the connect identifier specified
                #EXP-00000: Export terminated unsuccessfully
                qr/TNS:could\s+not\s+resolve\s+the\s+connect\s+identifier\s+specified/ => sub {
                    $isFail = 1;
                    print("ERROR: could not resolve connect identifier: $dbName\n");
                }
            ],
            [

                #EXP-00056: ORACLE error 12541 encountered
                #ORA-12541: TNS:no listener
                #EXP-00000: Export terminated unsuccessfully
                qr/no\s+listener/ => sub {
                    $isFail = 1;
                    print("ERROR: listener not start. Try commend: lsnrctl start ?\n");
                }
            ],
            [

                #IMP-00058: ORACLE error 12514 encountered
                #ORA-12514: TNS:listener does not currently know of service requested in connect descriptor
                qr/(?<=\n)ORA-12514:.*(?=\n)/ => sub {
                    $isFail = 1;
                    print("ERROR: listener does not know service of \"$dbName\", this service already startup?\n");
                }
            ],
            [

                #IMP-00033: Warning: Table "DEPT_FOR_IMP" not found in export file
                qr/IMP-00033: Warning: Table .+ not found in export file/s => sub {
                    $warningCount = $warningCount + 1;
                    my $match    = $spawn->match();
                    my @list     = split( /\n/, $match );
                    my $notFound = '';
                    my $count    = scalar(@list);

                    for ( my $i = 0 ; $i < $count ; $i++ ) {
                        $list[$i] =~ m/.+\"(.+)\".+/;
                        $notFound .= $1 . ", ";
                    }
                    $notFound =~ s/,\s$//;
                    print("\nWARING: table(s) \"$notFound\" not exist in file \"$sqlFile\".\n");
                    $spawn->exp_continue;
                }
            ],
            [

                #IMP-00015: following statement failed because the object already exists
                #"CREATE TABLE "DEPT_FOR_IMP" ("DEPTNO" NUMBER(2, 0), "DNAME" VARCHAR2(14), ""
                #"LOC" VARCHAR2(13))  PCTFREE 10 PCTUSED 40 INITRANS 1 MAXTRANS 255 STORAGE(I"
                # "NITIAL 65536 NEXT 1048576 MINEXTENTS 1 FREELISTS 1 FREELIST GROUPS 1 BUFFER"
                #  "_POOL DEFAULT)                    LOGGING NOCOMPRESS"
                qr/IMP-00015.+CREATE\sTABLE\s\".+?\"/s => sub {

                    #my $match = $spawn->match();
                    #$match =~ //s;
                    $warningCount = $warningCount + 1;
                    print("WARNING: some table(s) exist, skip.\n") if $tabExist == 0;
                    $tabExist = 1;
                    $spawn->exp_continue;
                }
            ]
        );

        if ( $spawn->exitstatus() ne 0 ) {
            $hasError = 1;
            $isFail   = 1;
            print("ERROR: imp failed.\n");
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

        my $sqlFileName = $self->{sqlFileName};
        my $hasLogon    = 0;

        my $sqlFH = IO::File->new("<$sqlFileName");

        if ( not defined($sqlFH) ) {
            $isFail = 1;
            print("ERROR: sql script file not exists:$self->{sqlDir}/$sqlFileName.\n");
        }
        else {
            $sqlFH->close();

            $spawn->expect(
                undef,
                [
                    qr/(?<=\n)Usage(\s*\d*):\s*SQLPLUS.*?(?=\n)/i => sub {
                        my $matchContent = DeployUtils->convToUTF8( $spawn->match() );
                        $hasHardError = 1;
                        $isFail       = 1;
                        $spawn->send("\cC\cC\n");
                        print("ERROR: $matchContent\n");
                        $spawn->exp_continue;
                    }
                ],
                [

                    #SP2-0310: unable to open file "oratest.scott/1.a.sql "
                    qr/(?<=\n)SP2-\d+:.*(?=\n)/ => sub {
                        my $SPError = DeployUtils->convToUTF8( $spawn->match() );

                        #$hasError = 1;
                        $hasHardError = 1;
                        $isFail       = 1;
                        print("\nERROR: $SPError\n");
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
                        print( DeployUtils->convToUTF8( $spawn->before() ) );
                        &$sqlEndHandle();
                    }
                ]
            );
        }

        if ( $hasLogon eq 1 ) {
            $spawn->clear_accum();

            #$self->{hasLogon} = 1;
            #print("Exection start > ");
            #$spawn->send("SET SQLP ''\r");
            #$spawn->send("select 'x' from dual;\r");
            $spawn->send(" SET TRIM ON\r");

            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->send(" SET DEFINE OFF\r");

            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->send(" SET LINESIZE 160\r");

            if ( $isAutoCommit == 1 ) {
                $spawn->expect( undef, [ $PROMPT => sub { } ] );
                $spawn->send(" SET AUTOCOMMIT ON\r");
            }

            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->send(" SET ECHO ON\r");

            if ( $sqlRunner eq 'sql' ) {
                $spawn->expect( undef, [ $PROMPT => sub { } ] );
                $spawn->send(" SET ENCODING $charSet\r");
            }

            $spawn->expect( undef, [ $PROMPT => sub { } ] );
            $spawn->send("SET SQLP ''\r");
            $self->{hasLogon} = 1;
            print("SQL> ");
            $spawn->send(" \@$sqlFileName\r");

            $spawn->send(" SET SQLP 'SQL> '\r");

            my $endDetectCount = 0;

            $spawn->expect(
                undef,

                [

                    #SP2-0027: Input is too long (> 2499 characters) - line ignored
                    qr/(?<=\n)SP2-\d+:.*(?=\n)/ => sub {
                        my $SPError = DeployUtils->convToUTF8( $spawn->match() );
                        $hasError     = 1;
                        $warningCount = $warningCount + 1;
                        print("\nERROR: $SPError\n");
                        $spawn->exp_continue;
                    }
                ],
                [
                    qr/\nSEVERE: Could not process url:file:/ => sub {
                        $hasError = 1;
                        $spawn->exp_continue;
                    }
                ],
                [
                    qr/(?<=\n)Warning:.*?(?=\n)/i => sub {
                        $hasWarn = 1;
                        $spawn->exp_continue;
                    }
                ],
                [

                    #ERROR at line 1:
                    #ORA-00904: "NAME": invalid identifier
                    #qr/\nERROR\s+at\s+line\s+\d+:\s*\nORA-\d+:[^\n]+/ => sub {
                    qr/\nERROR[^\n\r]*?:[\r\n]+ORA-\d+:[^\n\r]+/s => sub {
                        my $matchContent = DeployUtils->convToUTF8( $spawn->match() );
                        $matchContent =~ /^\n(ERROR.*?:.*?\x0A(ORA-\d+):.*)/s;
                        my $oraErrMsg = $1;
                        my $oraError  = $2;
                        $oraErrMsg =~ s/\s+/ /g;

                        $warningCount = $warningCount + 1;

                        #如果session被kill则自行推出并返回错误
                        if ( $oraError =~ /ORA-00028/i ) {
                            $sessionKilled = 1;
                            $spawn->send("exit;\n");
                            print("\nERROR: session has been killed.\n");
                        }

                        #如果错误可忽略则输出警告，否则输出错误
                        elsif ( $ignoreErrors =~ /$oraError/ ) {
                            $hasWarn = 1;
                        }
                        else {
                            $hasError = 1;
                            print("\nERROR: $oraErrMsg\n");
                        }
                        $spawn->exp_continue;
                    }
                ],
                [

                    #配合前面的换行符的匹配，当出现accum buffer里只剩下"SQL> "时，运行结束了
                    $PROMPT => sub {
                        $spawn->clear_accum();
                        &$sqlEndHandle();
                    }
                ],
                [
                    eof => sub {
                        $hasHardError = 1;
                        &$sqlEndHandle();
                    }
                ]
            );
        }
    }

    $self->{warningCount} = $warningCount;

    return $isFail;
}

1;
