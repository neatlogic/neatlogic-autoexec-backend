#!/usr/bin/perl
use strict;

package SqlplusExec;

use POSIX qw(uname);
use Carp;

#sqlplus的执行工具类，当执行出现ORA错误是会自动exit非0值，失败退出进程

sub new {
    my ( $type, %args ) = @_;
    my $self = {
        host     => $args{host},
        port     => $args{port},
        username => $args{username},
        password => $args{password},
        sysasm   => $args{sysasm},
        dbname   => $args{dbname},
        sid      => $args{sid},
        osUser   => $args{osUser},
        oraHome  => $args{oraHome}
    };

    my @uname  = uname();
    my $osType = $uname[0];
    $osType =~ s/\s.*$//;
    $self->{osType} = $osType;

    my $osUser  = $args{osUser};
    my $oraHome = $args{oraHome};

    my $isRoot = 0;
    if ( $> == 0 ) {

        #如果EUID是0，那么运行用户就是root
        $isRoot = 1;
    }
    $self->{isRoot} = $isRoot;

    bless( $self, $type );

    my $oraEnv = $self->getOraEnv($osUser);

    for my $envName ( 'ORACLE_BASE', 'ORACLE_HOME', 'ORACLE_SID', 'PATH', 'LD_LIBRARY_PATH' ) {
        my $envVal = $oraEnv->{$envName};
        if ( defined($envVal) and $envVal ne '' ) {
            $ENV{$envName} = $envVal;
        }
    }

    #$self->evalProfile();
    if ( defined( $self->{sid} ) and $self->{sid} ne '' ) {
        $ENV{ORACLE_SID} = $self->{sid};
        print( "INFO: Reset ORACLE_SID to " . $self->{sid} . "\n" );
    }
    if ( defined($oraHome) and $oraHome ne '' ) {
        $ENV{ORACLE_HOME} = $oraHome;
        my $path     = $ENV{PATH};
        my $oraBin   = File::Spec->canonpath("$oraHome/bin");
        my $patchBin = File::Spec->canonpath("$oraHome/OPatch");

        if ( $path !~ /\Q$patchBin\E/ ) {
            if ( $self->{osType} eq 'Windows' ) {
                $ENV{PATH} = "$patchBin;$path";
            }
            else {
                $ENV{PATH} = "$patchBin:$path";
            }
        }

        $path = $ENV{PATH};
        if ( $path !~ /\Q$oraBin\E/ ) {
            if ( $self->{osType} eq 'Windows' ) {
                $ENV{PATH} = "$oraBin;$path";
            }
            else {
                $ENV{PATH} = "$oraBin:$path";
            }
        }
    }

    my $oraSid     = $ENV{ORACLE_SID};
    my $sqlplusCmd = 'sqlplus -s -R 1 -L / as sysdba';
    if ( defined( $args{sysasm} ) ) {
        $sqlplusCmd = 'sqlplus -s -R 1 -L / as sysasm';
    }

    if ( $isRoot and defined($osUser) and $osUser ne 'root' and $osType ne 'Windows' ) {
        $sqlplusCmd = qq{su - $osUser -c "LANG=en_US.UTF-8 NLS_LANG=AMERICAN_AMERICA.AL32UTF8 ORACLE_SID=$oraSid $sqlplusCmd"};
    }

    if (    defined( $args{username} )
        and defined( $args{password} ) )
    {
        if ( not defined( $args{dbname} ) and not defined( $args{sid} ) ) {
            croak("ERROR: Must define attribute dbname or sid.\n");
        }

        if ( not defined( $args{host} ) ) {
            $args{host} = '127.0.0.1';
        }
        if ( not defined( $args{port} ) ) {
            $args{port} = 1521;
        }

        if ( not defined( $args{dbname} ) ) {
            $args{dbname} = $args{sid};
        }

        if ( defined( $args{dbname} ) ) {
            if ( $osType eq 'Windows' ) {
                $sqlplusCmd = qq(sqlplus -s -R 1 -L "$args{username}/\\"$args{password}\\""@//$args{host}:$args{port}/$args{dbname});
            }
            else {
                $sqlplusCmd = qq(sqlplus -s -R 1 -L '$args{username}/"$args{password}"'@//$args{host}:$args{port}/$args{dbname});
                if ( $isRoot and defined( $args{osUser} and $osUser ne 'root' and $osType ne 'Windows' ) ) {
                    $sqlplusCmd = qq(su - $osUser -c "ORACLE_SID=$oraSid sqlplus -s -R 1 -L '$args{username}/\"$args{password}\"'@//$args{host}:$args{port}/$args{dbname}");
                }
            }
        }
    }

    $self->{sqlplusCmd} = $sqlplusCmd;

    return $self;
}

sub getOraEnv {
    my ( $self, $osUser ) = @_;

    my $oraEnv = {};
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
                if ( $envName =~ /^ORACLE/ or $envName eq 'LD_LIBRARY_PATH' or $envName eq 'PATH' ) {
                    print("$envName=$envVal\n");
                }

                $oraEnv->{$envName} = $envVal;
            }
        }
    }

    return $oraEnv;
}

sub evalProfile {
    my ( $self, $osUser ) = @_;

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
                if ( $envName =~ /^ORACLE/ or $envName eq 'LD_LIBRARY_PATH' or $envName eq 'PATH' ) {
                    print("$envName=$envVal\n");
                }

                $ENV{$envName} = $envVal;
            }
        }
    }
}

sub _checkError {
    my ( $self, $sql, $output, $isVerbose ) = @_;
    my @lines      = split( /\n/, $output );
    my $linesCount = scalar(@lines);

    my $hasError = 0;

    for ( my $i = 0 ; $i < $linesCount ; $i++ ) {
        my $line = $lines[$i];
        if ( $isVerbose == 1 ) {
            if ( $line =~ /ORA-32004:/ ) {
                print("WARN: $line\n");
            }
            elsif ( $line =~ /ORA-\d+:/ or $line =~ /CRS-\d+:/ ) {
                $hasError = 1;
                print("WARN: $line\n");
            }
            else {
                print("$line\n");
            }
        }
        else {
            if ( $line =~ /ORA-32004:/ ) {
                print("WARN: $line\n");
            }
            elsif ( $line =~ /ORA-\d+:/ or $line =~ /CRS-\d+:/ ) {
                $hasError = 1;
                print("WARN: $line\n");
            }
        }
    }
    print("----------------------------------------------------------\n");

    if ( $hasError == 1 ) {
        if ( $sql =~ /^\s*shutdown\b/is ) {
            if ( $output =~ /ORACLE instance shut down/is ) {
                $hasError = 0;
            }
            elsif ( $output =~ /ORA-01034:/is ) {
                $hasError = 0;
            }
        }
        elsif ( $sql =~ /^\s*startup\b/is or $sql =~ /^\s*alter\s+database\s+open\b/is ) {
            if ( $output =~ /already open/is ) {
                $hasError = 0;
            }
            elsif ( $output =~ /ORA-01531:/is ) {
                $hasError = 0;
            }
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
        if ( $line =~ /^ERROR/ ) {
            if ( $lines[ $pos + 1 ] =~ /^ORA-\d+:/ ) {
                $hasError = 1;
                print( $line,              "\n" );
                print( $lines[ $pos + 1 ], "\n" );
            }
        }

        if ( $line =~ /^[-\s]+$/ ) {
            $hasData = 1;
            last;
        }
    }

    if ( $hasData == 1 ) {
        $pos = $pos - 1;
    }

    for ( my $i = $pos ; $i < $linesCount ; $i++ ) {
        my $line = $lines[$i];

        #错误识别
        #ERROR at line 1:
        #ORA-00907: missing right parenthesis
        if ( $line =~ /^ERROR/ ) {
            if ( $lines[ $i + 1 ] =~ /^ORA-\d+:/ ) {
                $hasError = 1;
                print( $line,            "\n" );
                print( $lines[ $i + 1 ], "\n" );
            }
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
            my $lineLen = length($line);
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

    $ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
    $ENV{LANG}     = 'en_US.UTF-8';

    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};
    my $parseData = $args{parseData};

    if ( $sql !~ /;\s*$/ ) {
        $sql = $sql . ';';
    }

    my $formatSetting = 'set linesize 256 pagesize 9999 echo off feedback off tab off trimout on underline on wrap on;';
    my $sqlplusCmd    = $self->{sqlplusCmd};
    if ( not defined($parseData) or $parseData == 0 ) {

        #$sqlplusCmd =~ s/sqlplus -s -R 1 -L /sqlplus -R 1 -L /;
        $formatSetting = 'set linesize 1024 pagesize 9999 echo on;';
    }

    my $sqlFH;
    my $cmd;

    if ( $self->{osType} ne 'Windows' ) {
        $cmd = qq{$sqlplusCmd << "EOF"
               $formatSetting
               $sql
               exit;
               EOF
              };
        $cmd =~ s/^\s*//mg;
    }
    else {
        use File::Temp;
        $sqlFH = File::Temp->new( UNLINK => 1, SUFFIX => '.sql' );
        my $fname = $sqlFH->filename;
        print $sqlFH ( $formatSetting, "\n" );
        print $sqlFH ( $sql,           "\n" );
        print $sqlFH ("exit;\n");
        $sqlFH->close();

        $cmd = qq{$sqlplusCmd @"$fname"};
    }

    if ($isVerbose) {
        print("INFO: Execute sql:\n");
        print( $sql, "\n" );
        print("----------------------------------------------------------\n");

        #my $len = length($sql);
        #print( '=' x $len, "\n" );
    }

    my $output = `$cmd`;
    my $status = $?;

    if ( $status != 0 ) {
        print("ERROR: Execute cmd failed\n $output\n");
        print("----------------------------------------------------------\n");
        return ( undef, undef, $status );
    }

    if ($parseData) {
        return $self->_parseOutput( $output, $isVerbose );
    }
    else {
        return $self->_checkError( $sql, $output, $isVerbose );
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
