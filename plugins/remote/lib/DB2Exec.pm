#!/usr/bin/env perl
use strict;

package DB2Exec;

use POSIX qw(uname);
use Carp;
use File::Temp;
use File::Basename;
use IO::Socket;
use IO::Socket::INET;

#sqlplus的执行工具类，当执行出现ORA错误是会自动exit非0值，失败退出进程

sub new {
    my ( $type, %args ) = @_;
    my $self = {
        host        => $args{host},
        port        => $args{port},
        username    => $args{username},
        password    => $args{password},
        dbname      => $args{dbname},
        db2instance => $args{db2instance},
        locale      => $args{locale},
        osUser      => $args{osUser},
        db2Home     => $args{db2Home},
        toolsDir    => $args{toolsDir},
        dbVersion   => $args{dbVersion}
    };

    if ( not defined( $args{dbname} ) ) {
        croak("ERROR: Must define attribute dbname.\n");
    }

    my @uname  = uname();
    my $osType = $uname[0];
    $osType =~ s/\s.*$//;
    $self->{osType} = $osType;

    my $osUser  = $args{osUser};
    my $db2Home = $args{db2Home};

    my $isRoot = 0;
    if ( $> == 0 ) {

        #如果EUID是0，那么运行用户就是root
        $isRoot = 1;
    }
    $self->{isRoot} = $isRoot;

    bless( $self, $type );

    my $db2Env = $self->getDB2Env($osUser);

    for my $envName ( 'DB2_HOME', 'DB2LIB', 'IBM_DB_LIB', 'IBM_DB_HOME', 'IBM_DB_DIR', 'IBM_DB_INCLUDE', 'DB2INSTANCE', 'PATH', 'LD_LIBRARY_PATH' ) {
        my $envVal = $db2Env->{$envName};
        if ( defined($envVal) and $envVal ne '' ) {
            $ENV{$envName} = $envVal;
        }
    }

    $ENV{LANG} = 'en_US.UTF-8';
    my $codePage = '1208';
    $ENV{DB2CODEPAGE} = $codePage;
    $ENV{DB2OPTIONS}  = '-td;';

    if ( defined( $self->{db2instance} ) and $self->{db2instance} ne '' ) {
        $ENV{DB2INSTANCE} = $self->{db2instance};
        print( "INFO: Reset DB2INSTANCE to " . $self->{db2instance} . "\n" );
    }
    if ( defined($db2Home) and $db2Home ne '' ) {
        $ENV{DB2_HOME} = $db2Home;

        my $path   = $ENV{PATH};
        my $db2Bin = File::Spec->canonpath("$db2Home/bin");

        $path = $ENV{PATH};
        if ( $path !~ /\Q$db2Bin\E/ ) {
            if ( $self->{osType} eq 'Windows' ) {
                $ENV{PATH} = "$db2Bin;$path";
            }
            else {
                $ENV{PATH} = "$db2Bin:$path";
            }
        }
    }

    $self->{isSu} = 0;

    if ( $isRoot and defined($osUser) and $osUser ne 'root' and $osType ne 'Windows' ) {
        $self->{isSU} = 1;
    }

    my $user   = $args{username};
    my $pass   = $args{password};
    my $dbName = $args{dbname};

    my $db2ConnCmd = '';

    if ( defined( $args{host} ) ) {
        if ( not defined($user) or $user eq '' or not defined($pass) or $pass eq '' ) {
            croak("ERROR: Must define user name and password while host is provided.\n");
        }

        if ( not defined( $args{port} ) ) {
            $args{port} = 50000;
        }

        my $host = $args{host};
        my $port = $args{port};

        eval {
            my $socket = IO::Socket::INET->new(
                PeerHost => $host,
                PeerPort => $port,
                Timeout  => 30
            );

            if ( defined($socket) ) {
                $socket->close();
            }
            else {
                croak("ERROR: Can not connect to $host:$port, $!\n");
            }
        };
        if ($@) {
            croak("ERROR: Can not connect to $host:$port, $!\n");
        }

        my $tmp         = File::Temp->new( TEMPLATE => 'NXXXXXXX', UNLINK => 1, SUFFIX => '' );
        my $catalogName = basename( $tmp->filename );

        END {
            #local $?是为了END的执行不影响进程返回值
            local $?;
            if ( defined($catalogName) and $catalogName ne '' ) {
                system("db2 UNCATALOG DB $catalogName > /dev/null 2>&1");
                system("db2 UNCATALOG NODE $catalogName > /dev/null 2>&1");
            }
        }

        $db2ConnCmd = '';
        $db2ConnCmd = $db2ConnCmd . qq{db2 CATALOG TCPIP NODE $catalogName REMOTE $host SERVER $port\n};
        $db2ConnCmd = $db2ConnCmd . qq{db2 CATALOG DATABASE $dbName AS $catalogName AT NODE $catalogName\n};
        $db2ConnCmd = $db2ConnCmd . qq{db2 CONNECT TO $catalogName USER '$user' USING '$pass'\n};

        my @pwdInfo = getpwuid($<);
        my $runUser = $pwdInfo[0];
        my $homeDir = $pwdInfo[7];

        my $toolsDir = $args{toolsDir};
        if ( defined($toolsDir) and $toolsDir ne '' ) {
            my $dbVersion = $args{dbVersion};
            my $db2Home   = "$toolsDir/db2-client";
            if ( defined($dbVersion) ) {
                $db2Home = "$db2Home-$dbVersion";

                #如果全版本号client不存在，则逐步缩短版本号寻找可用的db client目录
                while ( not -e $db2Home ) {
                    $db2Home =~ s/\.\d+$//;
                }
                $db2Home =~ s/-$//;
                if ( $db2Home eq "$toolsDir/db2-client" ) {
                    print("WARN: Can not find db client with version:db2-client-$dbVersion, fall back to default db client db2-client.\n");
                }
            }
            $db2Home = "$db2Home/sqllib";

            #TODO：DB2需要在执行用户的HOME目录下存在sqllib指向DB2的client，无法区分版本
            my $sqllibLnk = "$homeDir/sqllib";
            if ( not symlink( $db2Home, $sqllibLnk ) ) {
                my $lnkTarget = readlink($sqllibLnk);
                if ( $lnkTarget ne $db2Home ) {
                    print("WARN: DB2 $sqllibLnk link target $lnkTarget not equal $db2Home, recreate...\n");
                    unlink($sqllibLnk);
                    symlink( $db2Home, $sqllibLnk );
                }
            }

            $ENV{DB2_HOME}        = $db2Home;
            $ENV{DB2LIB}          = $db2Home . '/lib';
            $ENV{IBM_DB_LIB}      = $ENV{DB2LIB};
            $ENV{LD_LIBRARY_PATH} = $db2Home . '/lib64:' . $db2Home . '/bin:' . $ENV{LD_LIBRARY_PATH};
            $ENV{IBM_DB_HOME}     = $db2Home;
            $ENV{IBM_DB_DIR}      = $db2Home;
            $ENV{IBM_DB_INCLUDE}  = $db2Home . '/include';
            $ENV{PATH}            = $db2Home . '/bin:' . $db2Home . '/adm:' . $ENV{PATH};
            $ENV{DB2INSTANCE}     = $runUser;
        }

    }
    else {
        if ( defined($user) and $user ne '' ) {
            $db2ConnCmd = $db2ConnCmd . qq{db2 CONNECT TO $dbName USER '$user' USING '$pass'\n};
        }
        else {
            $db2ConnCmd = $db2ConnCmd . qq{db2 CONNECT TO $dbName\n};
        }
    }

    $self->{db2ConnCmd} = $db2ConnCmd;

    return $self;
}

sub getDB2Env {
    my ( $self, $osUser ) = @_;

    my $db2Env = {};
    if ( $self->{osType} eq 'Windows' ) {
        return;
    }

    my $evalCmd  = 'env';
    my $homePath = $ENV{HOME};
    if ( -f "$homePath/.profile" ) {
        $evalCmd = '. ~/.profile;env';
    }
    elsif ( -f "$homePath/.bash_profile" ) {
        $evalCmd = '. ~/.bash_profile;env';
    }

    if ( $self->{isRoot} == 1 and defined($osUser) and $osUser ne 'root' and $osUser ne '' and $self->{osType} ne 'Windows' ) {
        $evalCmd = "su - $osUser -c env";
    }

    $SIG{ALRM} = sub { die "eval user profile failed" };
    alarm(10);
    my $evalOutput = `$evalCmd`;
    my @envLines   = split( /\n/, $evalOutput );
    alarm(0);

    foreach my $line (@envLines) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line =~ /^(\w+)=(.*)$/ ) {
            my $envName = $1;
            my $envVal  = $2;
            if ( $envName ne 'PWD' ) {
                if ( $envName =~ /^DB/ or $envName eq 'LD_LIBRARY_PATH' or $envName eq 'PATH' ) {
                    print("$envName=$envVal\n");
                }

                $db2Env->{$envName} = $envVal;
            }
        }
    }

    return $db2Env;
}

sub getEnvStr {
    my ( $self ) = @_;
    my $envStr = '';
    for my $envName ( 'LANG', 'DB2CODEPAGE', 'DB2OPTIONS', 'DB2_HOME', 'DB2LIB', 'IBM_DB_LIB', 'IBM_DB_HOME', 'IBM_DB_DIR', 'IBM_DB_INCLUDE', 'DB2INSTANCE', 'PATH', 'LD_LIBRARY_PATH' ) {
        my $envVal = $ENV{$envName};
        if ( defined($envVal) and $envVal ne '' ) {
            $envStr = $envStr . qq{export $envName="$envVal"\n};
        }
    }

    return $envStr;
}

sub _checkError {
    my ( $self, $output, $isVerbose ) = @_;
    my $hasError = 0;
    my $sqlError;

    my @lines      = split( /\n/, $output );
    my $linesCount = scalar(@lines);

    my $hasError = 0;

    for ( my $i = 0 ; $i < $linesCount ; $i++ ) {
        my $line = $lines[$i];
        if ( $line =~ /SQLSTATE=(\d+)\s*$/ ) {
            $sqlError = $1;
            if ( $sqlError eq '02000' ) {
                print("WARN: $line");
            }
            else {
                $hasError = 1;
                print("ERROR: $line");
            }
        }
        elsif ( $line =~ /^SQL0911N The current transaction has been rolled back/ ) {
            print("WARN: $line");
        }
        elsif ( $line =~ /^SQL0803N/ or $line =~ /^SQL3550W/ ) {
            print("ERROR: $line");
            $hasError = 1;
        }
    }

    return ( undef, undef, $hasError );
}

sub _parseOutput {
    my ( $self, $output, $isVerbose ) = @_;
    my @lines      = split( /\n/, $output );
    my $linesCount = scalar(@lines);

    my $hasError        = 0;
    my @fieldNames      = ();
    my $fieldLenDesc    = {};
    my @rowsArray       = ();
    my $recordLineCount = 0;
    my @recordLineDescs = ();
    my $state           = 'heading';

    my $pos = 0;

    #Skip空行
    my $hasData = 0;
    for ( $pos = 0 ; $pos < $linesCount ; $pos++ ) {
        my $line = $lines[$pos];
        if ( $line =~ /SQLSTATE=(\d+)\s*$/ ) {
            $hasError = 1;
            print( $line, "\n" );
        }

        if ( $line =~ /^[-\s]+$/ ) {
            $hasData = 1;
            last;
        }
    }

    if ( $hasData == 1 ) {
        $pos = $pos - 1;
    }

    for ( my $i = $pos ; $i < $linesCount - 2 ; $i++ ) {
        my $line = $lines[$i];

        #错误识别
        #SQL0204N  "DB2INST1.TEST1" is an undefined name.  SQLSTATE=42704
        if ( $line =~ /SQLSTATE=(\d+)\s*$/ ) {
            $hasError = 1;
            print( $line, "\n" );
        }

        if ( $state eq 'heading' ) {

            #sqlplus的输出根据headsize的设置，一条记录会用多个行进行输出
            my $underLine = $lines[ $i + 1 ];
            if ( $underLine =~ /^\-[\-\s]+$/ ) {
                my $linePos = 0;

                #字段描述信息，分析行头时一行对应一个字段描述数组
                my @fieldDescs = ();

                #sqlplus的header字段下的-------，通过减号标记字段的显示字节宽度，通过此计算字段显示宽度，用于截取字段值
                #如果一行多个字段，字段之间的------中间会有空格，譬如：---- ---------
                my @underLineSegs = split( /\s+/, $underLine );
                for ( my $j = 0 ; $j < scalar(@underLineSegs) ; $j++ ) {
                    my $segment = $underLineSegs[$j];

                    #减号的数量就时字段的显示字节宽度
                    my $fieldLen = length($segment);

                    #linePos记录了当前行匹配的开始位置，根据字段的显示宽度从当前行抽取字段名
                    my $fieldName = substr( $line, $linePos, $fieldLen );
                    $fieldName =~ s/^\s+|\s+$//g;

                    #生成字段描述，记录名称、行中的开始位置、长度信息
                    my $fieldDesc = {};
                    $fieldDesc->{name}  = $fieldName;
                    $fieldDesc->{start} = $linePos;
                    $fieldDesc->{len}   = $fieldLen;

                    push( @fieldDescs, $fieldDesc );

                    #@fieldNames数组用于保留在sqlplus中字段的显示顺序
                    push( @fieldNames, $fieldName );

                    #$fieldLenDesc逐个字段记录了需要的最大显示宽度（会根据每行的字段值的长度，取大值进行修改）,用于显示
                    $fieldLenDesc->{$fieldName} = length($fieldName);

                    $linePos = $linePos + $fieldLen + 1;
                }
                push( @recordLineDescs, \@fieldDescs );
                $recordLineCount++;
                $i++;
            }
            else {
                #当前行下一行不是------，则代笔当前行是数据行，退回上一行
                $i--;
                $state = 'row';
                next;

                #行头分析完成，进入行处理
            }
        }
        else {
            my $row = {};

            #一个数据记录sqlplus根据字段的长度进行多行显示，跟行头的多行显示一致，根据行头分析的多行字段描述抽取字段值数据
            #my $lineLen = length($line);
            for ( my $k = 0 ; $k < $recordLineCount ; $k++ ) {
                $line = $lines[ $i + $k ];

                #获取当前行对应的字段描述
                my $fieldDescs = $recordLineDescs[$k];

                foreach my $fieldDesc (@$fieldDescs) {

                    #根据字段描述的行中的开始位置和长度，substr抽取字段值
                    my $val = substr( $line, $fieldDesc->{start}, $fieldDesc->{len} );
                    if ( defined($val) ) {
                        $val =~ s/^\s+|\s+$//g;
                    }
                    else {
                        $val = '';
                    }

                    my $fieldName = $fieldDesc->{name};
                    $row->{$fieldName} = $val;

                    #如果字段值的长度比$fieldLenDesc记录的大，则取大值，让显示该字段列时有足够的字节宽度
                    my $valLen = length($val);
                    if ( $valLen > $fieldLenDesc->{$fieldName} ) {
                        $fieldLenDesc->{$fieldName} = $valLen;
                    }
                }
            }

            #下标更新到下一条记录
            if ( $recordLineCount > 1 ) {
                $i = $i + $recordLineCount;
            }

            #完成一条记录的抽取，保存到行数组，进入下一条记录的处理
            push( @rowsArray, $row );
        }
    }

    if ( $isVerbose == 1 ) {
        my $fieldCount = scalar(@fieldNames);
        my $rowCount   = scalar(@rowsArray);

        #print head
        foreach my $field (@fieldNames) {
            printf( '-' x $fieldLenDesc->{$field} );
            print(' ');
        }
        if ( $fieldCount > 0 ) {
            print("\n");
        }
        foreach my $field (@fieldNames) {
            printf( "%-$fieldLenDesc->{$field}s ", $field );
        }
        if ( $fieldCount > 0 ) {
            print("\n");
        }

        foreach my $field (@fieldNames) {
            printf( '-' x $fieldLenDesc->{$field} );
            print(' ');
        }
        if ( $fieldCount > 0 ) {
            print("\n");
        }

        #print row
        foreach my $row (@rowsArray) {
            foreach my $field (@fieldNames) {
                printf( "%-$fieldLenDesc->{$field}s ", $row->{$field} );
            }
            print("\n");
        }

        if ( $rowCount > 0 ) {
            foreach my $field (@fieldNames) {
                printf( '-' x $fieldLenDesc->{$field} );
                print(' ');
            }
            print("\n\n");
        }
        else {
            print("----------------\n");
            print("no rows selected\n");
            print("----------------\n\n");
        }
    }

    if ($hasError) {
        print("ERROR: Sql execution failed.\n");
    }

    if ( scalar(@rowsArray) > 0 ) {
        return ( \@fieldNames, \@rowsArray, $hasError );
    }
    else {
        return ( undef, undef, $hasError );
    }
}

sub _execSql {
    my ( $self, %args ) = @_;

    $ENV{LANG} = 'en_US.UTF-8';

    my $sql        = $args{sql};
    my $db2Cmd     = $self->{db2Cmd};
    my $db2ConnCmd = $self->{db2ConnCmd};
    my $isSu       = $self->{isSu};

    my $isVerbose = $args{verbose};
    my $parseData = $args{parseData};

    if ( $sql !~ /;\s*$/ ) {
        $sql = $sql . ';';
    }

    my $sqlFH;
    my $cmd;

    use File::Temp;
    $sqlFH = File::Temp->new( UNLINK => 1, SUFFIX => '.sql' );
    my $fname = $sqlFH->filename;
    chmod( 0644, $fname );
    print $sqlFH ( $sql, "\n" );
    $sqlFH->close();

    if ($isVerbose) {
        print("INFO: Execute sql:\n");
        print( $sql, "\n" );
        print("----------------------------------------------------------\n");
    }

    my $output = '';
    if ( $isSu == 0 ) {
        my $connStatus = system($db2ConnCmd);
        if ( $connStatus != 0 ) {
            print("ERROR: Connect to db failed.\n");
            return ( undef, undef, $connStatus );
        }

        $output = `db2 -mf '$fname'`;
        my $status = $?;

        if ( $status != 0 ) {
            print("ERROR: Execute sql failed.\n$output\n");
            print("----------------------------------------------------------\n");
            return ( undef, undef, $status );
        }
        if($connStatus == 0) {
            system("db2 terminate");
        }
    }
    else {
        my $osUser = $self->{osUser};
        my $cmd;
        if ($self->{osType} eq 'Linux') {
            $cmd    = qq{su -m $osUser << "EOF"
                $db2ConnCmd
                db2 -mf '$fname'
                db2 terminate
                exit
                EOF
                };
        }
        else {
            my $envStr = $self->getEnvStr();
            $cmd    = qq{su -m $osUser << "EOF"
                $envStr
                $db2ConnCmd
                db2 -mf '$fname'
                db2 terminate
                exit
                EOF
                };
        }
        $cmd =~ s/^\s*//mg;
        $output = `$cmd`;
    }

    if ($parseData) {
        return $self->_parseOutput( $output, $isVerbose );
    }
    else {
        if($isVerbose == 1){
            print($output, "\n");
        }
        return $self->_checkError( $output, $isVerbose );
    }
}

#运行查询sql，返回行数组, 如果vebose=1，打印行数据
sub query {
    my ( $self, %args ) = @_;
    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};

    if ( not defined($isVerbose) ) {
        $isVerbose = 1;
    }

    my ( $fieldNames, $rows, $status ) = $self->_execSql( sql => $sql, verbose => $isVerbose, parseData => 1 );

    return ( $status, $rows );
}

#运行非查询的sql，如果verbose=1，直接输出sqlplus执行的日志
sub do {
    my ( $self, %args ) = @_;
    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};

    if ( not defined($isVerbose) ) {
        $isVerbose = 1;
    }

    my ( $fieldNames, $rows, $status ) = $self->_execSql( sql => $sql, verbose => $isVerbose, parseData => 0 );
    return $status;
}

1;
