#!/usr/bin/perl
use strict;

package SqlplusExec;

use Data::Dumper;

#sqlplus的执行工具类，当执行出现ORA错误是会自动exit非0值，失败退出进程

sub new {
    my ( $type, %args ) = @_;
    my $self = {
        host     => $args{host},
        port     => $args{port},
        username => $args{username},
        password => $args{password},
        dbname   => $args{dbname},
        sid      => $args{sid}
    };

    my $connStr = '/ as sysdba';
    if (    defined( $args{host} )
        and defined( $args{username} )
        and defined( $args{password} ) )
    {
        if ( not defined( $args{port} ) ) {
            $args{port} = 1521;
        }

        if ( defined( $args{dbname} ) ) {
            $connStr = "'$args{username}/\"$args{password}\"'\@//$args{host}:$args{port}/$args{dbname}";
        }
    }

    $self->{connStr} = $connStr;

    bless( $self, $type );
    $self->evalProfile();
    if ( defined( $self->{sid} ) and $self->{sid} ne '' ) {
        $ENV{ORACLE_SID} = $self->{sid};
        print( "INFO: Reset ORACLE_SID to " . $self->{sid} . "\n" );
    }

    return $self;
}

sub evalProfile {
    my ($self) = @_;

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
    my @envLines = split( /\n/, $evalOutput );
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

sub _parseOutput {
    my ( $self, $output, $isVerbose ) = @_;
    $output =~ s/^\s*//;
    my @lines = split( /\n/, $output );
    my $linesCount = scalar(@lines);

    my @lines = split( /\n/, $output );
    my $linesCount = scalar(@lines);

    my $hasError     = 0;
    my @fieldNames   = ();
    my $fieldLenDesc = {};
    my @rowsArray    = ();
    my $lineCount    = 0;
    my @lineDescs    = ();
    my $state        = 'heading';
    for ( my $i = 0 ; $i < $linesCount ; $i++ ) {
        my $line = $lines[$i];

        #错误识别
        #ERROR at line 1:
        #ORA-00907: missing right parenthesis
        if ( $line =~ /^ERROR at line \d+:/ ) {
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
                push( @lineDescs, \@fieldDescs );
                $lineCount++;
                $i++;
            }
            else {
                $state = 'row';

                #行头分析完成，进入正常数据记录分析，因为上面读取多了一行，把当前行回退，然后进入后续的处理
                $i--;
            }
        }
        else {
            my $row = {};

            #一个数据记录sqlplus根据字段的长度进行多行显示，跟行头的多行显示一致，根据行头分析的多行字段描述抽取字段值数据
            my $lineLen = length($line);
            for ( my $k = 0 ; $k < $lineCount ; $k++ ) {

                #获取当前行对应的字段描述
                my $fieldDescs = $lineDescs[$k];

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

                #获取下一行继续按行抽取字段值数据
                $i++;
                $line = $lines[$i];
            }

            #完成一条记录的抽取，保存到行数组，进入下一条记录的处理
            push( @rowsArray, $row );
        }
    }

    if ( $isVerbose == 1 ) {

        #print head
        foreach my $field (@fieldNames) {
            printf( "%-$fieldLenDesc->{$field}s ", $field );
        }
        print("\n");
        foreach my $field (@fieldNames) {
            printf( '-' x $fieldLenDesc->{$field} );
            print(' ');
        }
        print("\n");

        #print row
        foreach my $row (@rowsArray) {
            foreach my $field (@fieldNames) {
                printf( "%-$fieldLenDesc->{$field}s ", $row->{$field} );
            }
            print("\n");
        }
    }

    if ($hasError) {
        print("ERROR: Sql execution failed.\n");
        exit(-1);
    }

    if ( scalar(@rowsArray) > 0 ) {
        return ( \@fieldNames, \@rowsArray );
    }
    else {
        return;
    }
}

sub _execSql {
    my ( $self, %args ) = @_;
    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};
    my $parseData = $args{parseData};

    if ( $sql !~ /;$/ ) {
        $sql = $sql . ';';
    }

    my $cmd = qq{sqlplus -s -R 1 -L $self->{connStr} << "EOF"
               set linesize 256 pagesize 9999 echo off feedback off tab off trimout on underline on;
               $sql
               exit;
               EOF
              };

    $cmd =~ s/^\s*//mg;

    if ($isVerbose) {
        print("INFO: Execute sql:\n");
        print( $sql, "\n" );
        my $len = length($sql);
        print( '=' x $len, "\n" );
    }

    my $output = `$cmd`;

    if ( $? ne 0 ) {
        print("ERROR: Execute cmd failed\n $output\n");
        exit(-1);
    }

    if ($parseData) {
        return $self->_parseOutput( $output, $isVerbose );
    }
    elsif ($isVerbose) {
        print($output);
        return;
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

    my ( $fieldNames, $rows ) = $self->_execSql( sql => $sql, verbose => $isVerbose, parseData => 1 );

    return $rows;
}

#运行非查询的sql，如果verbose=1，直接输出sqlplus执行的日志
sub do {
    my ( $self, %args ) = @_;
    my $sql       = $args{sql};
    my $isVerbose = $args{verbose};

    if ( not defined($isVerbose) ) {
        $isVerbose = 1;
    }

    $self->_execSql( sql => $sql, verbose => $isVerbose, parseData => 0 );
    return;
}

1;

