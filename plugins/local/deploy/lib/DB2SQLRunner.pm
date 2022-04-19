#!/usr/bin/perl
use strict;

package DB2SQLRunner;

use FindBin;
use Expect;
use Encode;
use File::Basename;
use File::Temp;

use DeployUtils;
use SQLFileStatus;

our %ENCODING_TO_CCSID = (
    'ASCII'            => '367',
    'Big5'             => '950',
    'Big5_HKSCS'       => '950',
    'Big5_Solaris'     => '950',
    'CNS11643'         => '964',
    'Cp037'            => '37',
    'Cp273'            => '273',
    'Cp277'            => '277',
    'Cp278'            => '278',
    'Cp280'            => '280',
    'Cp284'            => '284',
    'Cp285'            => '285',
    'Cp297'            => '297',
    'Cp420'            => '420',
    'Cp424'            => '424',
    'Cp437'            => '437',
    'Cp500'            => '500',
    'Cp737'            => '737',
    'Cp775'            => '775',
    'Cp838'            => '838',
    'Cp850'            => '850',
    'Cp852'            => '852',
    'Cp855'            => '855',
    'Cp857'            => '857',
    'Cp860'            => '860',
    'Cp861'            => '861',
    'Cp862'            => '862',
    'Cp863'            => '863',
    'Cp864'            => '864',
    'Cp865'            => '865',
    'Cp866'            => '866',
    'Cp868'            => '868',
    'Cp869'            => '869',
    'Cp870'            => '870',
    'Cp871'            => '871',
    'Cp874'            => '874',
    'Cp875'            => '875',
    'Cp918'            => '918',
    'Cp921'            => '921',
    'Cp922'            => '922',
    'Cp930'            => '930',
    'Cp933'            => '933',
    'Cp935'            => '935',
    'Cp937'            => '937',
    'Cp939'            => '939',
    'Cp942'            => '942',
    'Cp942C'           => '942',
    'Cp943'            => '943',
    'Cp943C'           => '943',
    'Cp948'            => '948',
    'Cp949'            => '944',
    'Cp949C'           => '949',
    'Cp950'            => '950',
    'Cp964'            => '964',
    'Cp970'            => '970',
    'Cp1006'           => '1006',
    'Cp1025'           => '1025',
    'Cp1026'           => '1026',
    'Cp1046'           => '1046',
    'Cp1097'           => '1097',
    'Cp1098'           => '1098',
    'Cp1112'           => '1112',
    'Cp1122'           => '1122',
    'Cp1123'           => '1123',
    'Cp1140'           => '1140',
    'Cp1141'           => '1141',
    'Cp1142'           => '1142',
    'Cp1143'           => '1143',
    'Cp1144'           => '1144',
    'Cp1145'           => '1145',
    'Cp1146'           => '1146',
    'Cp1147'           => '1147',
    'Cp1148'           => '1148',
    'Cp1149'           => '1149',
    'Cp1250'           => '1250',
    'Cp1251'           => '1251',
    'Cp1252'           => '1252',
    'Cp1253'           => '1253',
    'Cp1254'           => '1254',
    'Cp1255'           => '1255',
    'Cp1256'           => '1256',
    'Cp1257'           => '1257',
    'Cp1258'           => '1251',
    'Cp1381'           => '1381',
    'Cp1383'           => '1383',
    'Cp33722'          => '33722',
    'EUC_CN'           => '1383',
    'EUC_JP'           => '5050',
    'EUC_KR'           => '970',
    'EUC_TW'           => '964',
    'GB2312'           => '1381',
    'GB18030'          => '1392',
    'GBK'              => '1386',
    'ISCII91'          => '806',
    'ISO2022CN'        => '965',
    'ISO2022_CN_CNS'   => '965',
    'ISO2022_CN_GB'    => '1383',
    'ISO2022CN_CNS'    => '965',
    'ISO2022CN_GB'     => '1383',
    'ISO2022JP'        => '5054',
    'ISO2022KR'        => '25546',
    'ISO8859_1'        => '819',
    'ISO8859_2'        => '912',
    'ISO8859_4'        => '914',
    'ISO8859_5'        => '915',
    'ISO8859_6'        => '1089',
    'ISO8859_7'        => '813',
    'ISO8859_8'        => '916',
    'ISO8859_9'        => '920',
    'ISO8859_15'       => '923',
    'ISO8859_15_FDIS'  => '923',
    'ISO-8859-15'      => '923',
    'JIS0201'          => '897',
    'JIS0208'          => '5052',
    'K018_R'           => '878',
    'KSC5601'          => '949',
    'MacArabic'        => '1256',
    'MacCentralEurope' => '1282',
    'MacCroatian'      => '1284',
    'MacCyrillic'      => '1283',
    'MacGreek'         => '1280',
    'MacHebrew'        => '1255',
    'MacIceland'       => '1286',
    'MacRomania'       => '1285',
    'MacTurkish'       => '1281',
    'MacUkraine'       => '1283',
    'MS874'            => '874',
    'MS932'            => '943',
    'MS936'            => '936',
    'MS949'            => '949',
    'MS950'            => '950',
    'MS950_HKSCS'      => 'NA',
    'SJIS'             => '932',
    'TIS620'           => '874',
    'US-ASCII'         => '367',
    'UTF8'             => '1208',
    'UTF-16'           => '1200',
    'UTF-16BE'         => '1200',
    'UTF-16LE'         => '1200',
    'UTF-8'            => '1208',
    'Unicode'          => '13488',
    'UnicodeBig'       => '13488'
);

sub new {
    my ( $pkg, $sqlFile, %args ) = @_;

    my $sqlFileStatus = $args{sqlFileStatus};
    my $dbInfo        = $args{dbInfo};
    my $charSet       = $args{charSet};
    my $logFilePath   = $args{logFilePath};
    my $toolsDir      = $args{toolsDir};
    my $tmpDir        = $args{tmpDir};

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

    my @pwdInfo = getpwuid($<);
    my $runUser = $pwdInfo[0];
    my $homeDir = $pwdInfo[7];

    if ( not -e "$homeDir/sqllib" ) {
        symlink( "$toolsDir/db2-client", "$homeDir/sqllib" );
    }

    $ENV{DB2_HOME}        = "$toolsDir/db2-client";
    $ENV{DB2LIB}          = $ENV{DB2_HOME} . '/lib';
    $ENV{IBM_DB_LIB}      = $ENV{DB2LIB};
    $ENV{LD_LIBRARY_PATH} = $ENV{DB2_HOME} . '/lib64:' . $ENV{DB2_HOME} . '/bin:' . $ENV{LD_LIBRARY_PATH};
    $ENV{IBM_DB_HOME}     = $ENV{DB2_HOME};
    $ENV{IBM_DB_DIR}      = $ENV{DB2_HOME};
    $ENV{IBM_DB_INCLUDE}  = $ENV{DB2_HOME} . '/include';
    $ENV{PATH}            = $ENV{DB2_HOME} . '/bin:' . $ENV{DB2_HOME} . '/adm:' . $ENV{PATH};
    $ENV{DB2INSTANCE}     = $runUser;

    #通过环境变量DB2CODEPAGE设置client的charset，1208是UTF-8
    #my $codePage = '1208';
    #if ( $charSet eq 'GBK' ) {
    #    $codePage = '1386';
    #}
    my $codePage = $ENCODING_TO_CCSID{$charSet};
    if ( not defined($codePage) ) {
        $codePage = '1208';
    }

    if ( defined($dbServerLocale) and ( $dbServerLocale eq '819' or $dbServerLocale =~ /ISO-8859-1/ ) ) {
        $codePage = 819;
    }

    $ENV{DB2CODEPAGE} = $codePage;

    $sqlFile =~ s/^\s*'|'\s*$//g;

    $self->{sqlFileStatus} = $sqlFileStatus;
    $self->{toolsDir}      = $toolsDir;
    $self->{tmpDir}        = $tmpDir;

    $self->{dbName}       = $dbName;
    $self->{dbType}       = $dbType;
    $self->{host}         = $host;
    $self->{port}         = $port;
    $self->{sqlFile}      = $sqlFile;
    $self->{charSet}      = $charSet;
    $self->{user}         = $user;
    $self->{pass}         = $pass;
    $self->{logFilePath}  = $logFilePath;
    $self->{isAutoCommit} = $isAutoCommit;
    $self->{hasLogon}     = 0;
    $self->{ignoreErrors} = $dbInfo->{ignoreErrors};

    if ( defined($sqlFile) and $sqlFile ne '' and $sqlFile ne 'test' ) {
        my $sqlDir      = dirname($sqlFile);
        my $sqlFileName = basename($sqlFile);
        $self->{sqlFileName} = $sqlFileName;
        chdir($sqlDir);
        mkdir('backup');
        $ENV{'BAKDIR'} = "$sqlDir/backup";

        #DB@OPTIONS, set autocommit off and verbose is on
        #procedure use terminator '@', otherwise ';'
        #在DB扩展参数里设置默认的sql和procedure的结束符号db2SqlTerminator, db2ProcTerminator
        #可以在sql的开头使用SET TERMINATOR xx来定义sql的结束符号
        my $sqlTerminator = $dbInfo->{db2SqlTerminator};
        if ( not defined($sqlTerminator) or $sqlTerminator eq '' ) {
            $sqlTerminator = ';';
        }

        my $procTerminator = $dbInfo->{db2ProcTerminator};
        if ( not defined($procTerminator) or $procTerminator eq '' ) {
            $procTerminator = '@';
        }

        my $db2Options = '';
        if ( $sqlFileName =~ /\.proc\..*\.sql$/i or $sqlFileName =~ /\.proc$/i or $sqlFileName =~ /\.prc$/i ) {
            $db2Options = "-td$procTerminator -v -m";
        }
        else {
            $db2Options = "-td$sqlTerminator -v -m";
        }

        if ( $isAutoCommit == 1 ) {
            $db2Options = $db2Options . ' -c';
        }
        else {
            $db2Options = $db2Options . ' +c';
        }

        $ENV{DB2OPTIONS} = $db2Options;
    }

    my $tmp = File::Temp->new( TEMPLATE => 'NXXXXXXX', DIR => $tmpDir, UNLINK => 1, SUFFIX => '' );

    $self->{catalogFH} = $tmp;
    my $catalogFile = $tmp->filename;
    $self->{catalogFile} = $catalogFile;
    my $catalogName = basename( $tmp->filename );
    $self->{catalogName} = $catalogName;

    return $self;
}

sub test {
    my ($self) = @_;

    my $hasLogon = 0;

    my $tmpDir      = $self->{tmpDir};
    my $tmp         = File::Temp->new( TEMPLATE => 'NXXXXXXX', DIR => $tmpDir, UNLINK => 1, SUFFIX => '' );
    my $catalogName = basename( $tmp->filename );

    my $host   = $self->{host};
    my $port   = $self->{port};
    my $dbName = $self->{dbName};
    my $user   = $self->{user};

    END {
        #local $?是为了END的执行不影响进程返回值
        local $?;
        if ( defined($catalogName) and $catalogName ne '' ) {
            system("db2 UNCATALOG DB $catalogName > /dev/null 2>&1");
            system("db2 UNCATALOG NODE $catalogName > /dev/null 2>&1");
        }
    }

    #注意因为db2的命令需要在同一个父进程下，所以，system调用的写法特别关键
    #不能含有任何bash的操作符号，否则会导致system启动shell来运行命令，导致db2的父进程发生变化

    my $ret = 0;
    $ret = system("db2 CATALOG TCPIP NODE $catalogName REMOTE $host SERVER $port > /dev/null");

    if ( $ret eq 0 ) {
        $ret = system("db2 CATALOG DATABASE $dbName AS $catalogName AT NODE $catalogName > /dev/null");
    }

    if ( $ret ne 0 ) {
        my $errMsg = "ERROR: catalog $host:$port/$dbName with node name $catalogName failed.\n";
        print($errMsg);
    }
    else {
        my $user = $self->{user};
        my $pass = $self->{pass};

        #open( STDOUT, ">&CPOUT" );
        print("INFO: db2 CONNECT TO $catalogName($host:$port/$dbName) USER $user USING '******'\n");
        $ret = system("db2 CONNECT TO $catalogName USER $user USING '$pass' > /dev/null");

        if ( $ret ne 0 ) {
            print("ERROR: db2 $user\@//$host:$port/$dbName connection test failed.\n");
        }
        else {
            print("INFO: db2 $user\@//$host:$port/$dbName connection test success.\n");
            $hasLogon = 1;
            $self->{hasLogon} = 1;
        }
    }

    return $hasLogon;
}

sub run {
    my ($self)       = @_;
    my $logFilePath  = $self->{logFilePath};
    my $charSet      = $self->{charSet};
    my $sqlFile      = $self->{sqlFile};
    my $sqlFileName  = $self->{sqlFileName};
    my $catalogFile  = $self->{catalogFile};
    my $catalogFH    = $self->{catalogFH};
    my $isAutoCommit = $self->{isAutoCommit};

    my $pipeFile = $logFilePath;
    $pipeFile =~ s/\.log$//;
    $pipeFile = "$pipeFile.run.pipe";

    my ( $sqlError, $sqlErrMsg );
    my $hasError     = 0;
    my $hasWarn      = 0;
    my $isFail       = 0;
    my $warningCount = 0;
    my $ignoreErrors = $self->{ignoreErrors};

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
    my $sqlFH    = IO::File->new("<$sqlFileName");

    if ( not defined($sqlFH) ) {
        $isFail = 1;
        print("ERROR: sql script file not exists:$sqlFileName.\n");
    }
    else {
        $sqlFH->close();

        my $catalogName = $self->{catalogName};
        my $host        = $self->{host};
        my $port        = $self->{port};
        my $dbName      = $self->{dbName};

        END {

            #local $?是为了END的执行不影响进程返回值
            local $?;
            if ( defined($catalogName) and $catalogName ne '' ) {
                open( STDOUT, '>/dev/null' );
                open( STDERR, '>/dev/null' );
                system("db2 UNCATALOG DB $catalogName");
                system("db2 UNCATALOG NODE $catalogName");
            }
            if ( defined($catalogFH) ) {
                $catalogFH->close();
            }
        }

        my $pid = fork();
        if ( $pid == 0 ) {

            #注意因为db2的命令需要在同一个父进程下，所以，system调用的写法特别关键
            #不能含有任何bash的操作符号，否则会导致system启动shell来运行命令，导致db2的父进程发生变化
            open( STDOUT, sprintf( ">&=%d", $catalogFH->fileno() ) );
            open( STDERR, sprintf( ">&=%d", $catalogFH->fileno() ) );

            my $ret = 0;
            $ret = system("db2 CATALOG TCPIP NODE $catalogName REMOTE $host SERVER $port");

            if ( $ret eq 0 ) {
                $ret = system("db2 CATALOG DATABASE $dbName AS $catalogName AT NODE $catalogName");
            }

            if ( $ret ne 0 ) {
                $hasError = 1;
                my $errMsg = "ERROR: catalog $host:$port/$dbName with node name $catalogName failed.\n";
                print($errMsg);
            }
            else {
                my $user = $self->{user};
                my $pass = $self->{pass};

                $ret = system("db2 CONNECT TO $catalogName USER $user USING '$pass'");
                if ( $ret ne 0 ) {
                    $hasError = 1;
                    print("ERROR: connect to $host:$port/$dbName with name $catalogName failed.\n");
                }
                else {
                    $hasLogon = 1;
                }
            }

            if ( $hasLogon == 1 ) {
                $self->{hasLogon} = 1;
                print("Exection start > \n");

                my $ret = 0;

                if ( $sqlFileName =~ /\.bnd$/ ) {
                    $ret = system("db2 bind '$sqlFileName'");
                }
                else {
                    $ret = system("db2 -mf '$sqlFileName'");
                }

                if ( $ret > 255 ) {
                    $ret = $ret >> 8;
                }

                if ( $ret eq 1 or $ret eq 2 ) {
                    print("WARN: some warn occurred, check the log for detail.\n");
                    $ret = system('db2 commit');
                }
                elsif ( $ret ne 0 ) {

                    #SQL 错误
                    my $opt;
                    print("ERROR: some error occurred, check the log for detail.\n");

                    if ( $isAutoCommit == 1 ) {
                        print("\nWARN: autocommit is on, select 'ignore' to continue, 'abort' to abort the job.\n");
                        if ( exists( $ENV{IS_INTERACT} ) ) {
                            my $sqlFileStatus = $self->{sqlFileStatus};
                            $opt = $sqlFileStatus->waitInput( 'Execute failed, select action(ignore|abort)', $pipeFile );
                        }

                        $opt = 'abort' if ( not defined($opt) );

                        if ( $opt eq 'abort' ) {
                            $isFail = 1;
                        }
                    }
                    else {
                        if ( exists( $ENV{IS_INTERACT} ) ) {
                            my $sqlFileStatus = $self->{sqlFileStatus};
                            $opt = $sqlFileStatus->waitInput( 'Execute failed, select action(commit|rollback)', $pipeFile );
                        }

                        $opt = 'rollback' if ( not defined($opt) );

                        $ret = system("db2 $opt");
                        if ( $opt eq 'rollback' ) {
                            $isFail = 1;
                        }
                    }
                }
                else {
                    $ret = system('db2 commit');
                }

                if ( $ret ne 0 ) {
                    $isFail = 1;
                }

                open( STDOUT, '/dev/null' );
                open( STDERR, '/dev/null' );
                system("db2 UNCATALOG DB $catalogName");
                system("db2 UNCATALOG NODE $catalogName");
                open( STDOUT, sprintf( ">&=%d", $catalogFH->fileno() ) );
                open( STDERR, sprintf( ">&=%d", $catalogFH->fileno() ) );
            }
            else {
                $isFail = 1;
            }

            exit($isFail);
        }
        else {

            #等待执行子进程结束，并循环读取子进程的输出
            my $execOut = IO::File->new("<$catalogFile");
            my $line;
            my $lastLine;
            my $tLine;
            my $toBeRollback = 0;

            my $getLines = sub {
                if ( defined($execOut) ) {
                    while ( $line = $execOut->getline() ) {
                        if ( $line ne '' ) {
                            $lastLine = $line;
                        }

                        if ( $charSet ne 'UTF-8' ) {
                            $tLine = Encode::encode( "utf-8", Encode::decode( lc($charSet), $line ) );
                        }
                        else {
                            $tLine = $line;
                        }

                        print($tLine);

                        if ( $tLine =~ /SQLSTATE=(\d+)\s*$/ ) {
                            $sqlError     = $1;
                            $warningCount = $warningCount + 1;
                            if ( $sqlError eq '02000' or $ignoreErrors =~ /$sqlError/ ) {
                                $hasWarn = 1;
                                print("WARN: error ocurred, see detail in pre line.\n");
                            }
                            else {
                                $hasError = 1;
                                print("ERROR: error ocurred, see detail in pre line.\n");
                            }
                        }
                        elsif ( $tLine = /^SQL0911N The current transaction has been rolled back/ ) {
                            $warningCount = $warningCount + 1;
                            $toBeRollback = 1;
                        }
                    }
                }
            };

            #循环检测子进程是否在运行
            while ( waitpid( $pid, 1 ) == 0 ) {
                &$getLines();
                if ( $toBeRollback == 1 and -e $pipeFile ) {
                    my $pipeFh = IO::File->new(">>$pipeFile");
                    if ( defined($pipeFh) ) {
                        print("ERROR: detect auto rollback, rollback auto and return failed.\n");
                        print $pipeFh ("rollback\n");
                    }
                }

                sleep(2);
            }
            my $exitCode = $?;
            if ( $exitCode > 255 ) {
                $exitCode = $exitCode >> 8;
            }

            &$getLines();

            if ( $exitCode ne 0 ) {
                $isFail = 1;
            }
            $ENV{WARNING_COUNT} = $warningCount;
            $ENV{HAS_ERROR}     = $hasError;
        }
    }

    return $isFail;
}

1;

