#!/usr/bin/perl
use strict;

package Utils;
use FindBin;
use POSIX;
use IO::File;
use IO::Select;
use Sys::Hostname;
use File::Copy;
use File::Find;
use File::Path;
use Encode;
use Mojo::JSON qw(to_json from_json);
use Encode::Guess;
use File::Basename;
use Cwd;
use File::Glob qw(bsd_glob);
use Data::Dumper;

my $READ_TMOUT = 86400;
my $SYSTEM_CONF;
my $TERM_CHARSET;

sub convToUTF8 {
    my ($content) = @_;
    if ( not defined($TERM_CHARSET) ) {
        my $lang = $ENV{LANG};
        if ( not defined($lang) or $lang eq '' ) {
            $ENV{LANG} = 'en_US.UTF-8';
            $TERM_CHARSET = 'utf-8';
        }
        else {
            $TERM_CHARSET = lc( substr( $lang, rindex( $lang, '.' ) + 1 ) );
            $TERM_CHARSET = 'utf-8' if ( $TERM_CHARSET eq 'utf8' );
        }
    }

    if ( $TERM_CHARSET ne 'utf-8' ) {
        $content = Encode::encode( 'utf-8', Encode::decode( $TERM_CHARSET, $content ) );
    }

    return $content;
}

sub url_encode {
    my $rv = shift;
    $rv =~ s/([^a-z\d\Q.-_~ \E])/sprintf("%%%2.2X", ord($1))/geix;
    $rv =~ tr/ /+/;
    return $rv;
}

sub url_decode {
    my $rv = shift;
    $rv =~ tr/+/ /;
    $rv =~ s/\%([a-f\d]{2})/ pack 'C', hex $1 /geix;
    return $rv;
}

sub escapeQuote {
    my ($line) = @_;
    $line =~ s/([\{\}\(\)\[\]\'\"\$\s\&\!])/\\$1/g;
    return $line;
}

sub escapeQuoteWindows {
    my ($line) = @_;
    $line =~ s/([\'\"\$\&\^\%])/^$1/g;
    return $line;
}

#读取命令执行后管道的输出
sub getPipeOut {
    my ( $cmd, $isVerbose ) = @_;
    my ( $line, @outArray );

    my $exitCode = 0;
    my $pid      = open( PIPE, "$cmd |" );
    if ( defined($pid) ) {
        while ( $line = <PIPE> ) {
            if ( $isVerbose == 1 ) {
                print($line);
            }

            chomp($line);
            push( @outArray, $line );
        }
        waitpid( $pid, 0 );
        $exitCode = $?;

        close(PIPE);
    }

    if ( not defined($pid) or $exitCode != 0 and $isVerbose == 1 ) {
        my $len = scalar(@outArray);
        for ( my $i = 0 ; $i < 10 and $i < $len ; $i++ ) {
            print($line);
        }
        print("...\n");
        die("ERROR: Execute '$cmd' failed.\n");
    }

    return \@outArray;
}

#读取命令执行后管道的输出
sub teePipeOut {
    my ($cmd) = @_;
    return getPipeOut( $cmd, 1 );
}

#读取命令执行后管道的输出
sub handlePipeOut {
    my ( $cmd, $callback, $isVerbose, $execDesc ) = @_;

    my $line;

    my $exitCode = 0;
    if ($isVerbose) {
        if ( defined($execDesc) ) {
            print("$execDesc\n");
            print("----------------------------------------------------------------------\n");
        }
        else {
            print("$cmd\n");
            print("----------------------------------------------------------------------\n");
        }
    }

    my $pid = open( PIPE, "$cmd |" );
    if ( defined($pid) ) {
        while ( $line = <PIPE> ) {
            if ( $isVerbose == 1 ) {
                print($line);
            }
            chomp($line);
            if ( defined($callback) ) {
                &$callback($line);
            }
        }
        waitpid( $pid, 0 );
        $exitCode = $?;

        close(PIPE);
    }

    if ( not defined($pid) or $exitCode != 0 ) {
        if ( defined($execDesc) and $execDesc ne '' ) {
            die("ERROR: Execute '$execDesc' failed.\n");
        }
        else {
            die("ERROR: Execute '$cmd' failed.\n");
        }
    }

    return $exitCode;
}

#添加进程事件处理响应函数, 会保留并执行原来的逻辑
sub sigHandler {
    my $subref = pop(@_);
    foreach my $sig (@_) {
        my $original = $SIG{$sig} || sub { };
        $SIG{$sig} = sub {
            $subref->();
            $original->();
        };
    }
}

sub isatty {
    my $isTTY = open( my $tty, '+<', '/dev/tty' );
    if ( defined($tty) ) {
        close($tty);
    }
    return $isTTY;
}

sub doInteract {
    my ( $pipeFile, %args ) = @_;

    my $message = $args{message};    # 交互操作文案
    my $opType  = $args{opType};     # 类型：button|input|select|mselect
    my $title   = $args{title};      # 交互操作标题
    my $opts    = $args{options};    # 操作列表json数组，譬如：["commit","rollback"]
    my $role    = $args{role};       # 可以操作此操作的角色，如果空代表不控制
    $args{pipeFile} = $pipeFile;

    my $optsMap = {};

    for my $opt (@$opts) {
        $optsMap->{$opt} = 1;
    }
    my $pipeDescFile = "$pipeFile.json";

    my $pipe;

    END {
        local $?;
        local $?;
        if ( defined($pipe) ) {
            $pipe->close();
        }
        unlink($pipeFile);
        unlink($pipeDescFile);
    }

    my $userId;
    my $enter;

    if ( -e $pipeFile ) {
        unlink($pipeFile);
    }

    my $pipeDescFH = IO::File->new(">$pipeDescFile");
    if ( not defined($pipeDescFH) ) {
        die("ERROR: Create file $pipeDescFile failed $!\n");
    }
    print $pipeDescFH ( to_json( \%args ) );
    close($pipeDescFH);

    POSIX::mkfifo( $pipeFile, 0700 );
    $pipe = IO::File->new("+<$pipeFile");

    if ( defined($pipe) ) {
        my $hasGetInput = 0;
        while ( $hasGetInput == 0 ) {
            print("$message\n");

            my $select       = IO::Select->new( $pipe, \*STDIN );
            my @inputHandles = $select->can_read($READ_TMOUT);

            if ( not @inputHandles ) {
                print("\nWARN: Wait user input timeout.\n");
                $enter = 'force-exit';
                if ( defined($pipe) ) {
                    $pipe->close();
                }
                unlink($pipeFile);
                die("ERROR: Read time out");
            }

            foreach my $inputHandle (@inputHandles) {
                $enter = $inputHandle->getline();

                if ( not defined($enter) ) {
                    $enter = 'force-exit';
                }

                $enter =~ s/^\s*|\s*$//g;
                if ( $enter =~ /^\[(.*?)\]# (.*)$/ ) {
                    $userId = $1;
                    $enter  = $2;
                }
                print("INFO: Get input:$enter\n");

                if ( $opType eq 'input' or $optsMap->{$enter} == 1 or $enter eq 'force-exit' ) {
                    $hasGetInput = 1;
                    last;
                }
                else {
                    print("WARN: Invalid input value:$enter, try again.\n");
                }
            }
        }
    }
    else {
        die("ERROR: Can not get input $!\n");
    }

    if ( defined($pipe) ) {
        $pipe->close();
    }
    unlink($pipeFile);
    unlink($pipeDescFile);

    if ( $enter eq 'force-exit' ) {
        undef($enter);
    }

    return ( $userId, $enter );
}

sub decideOption {
    my ( $msg, $pipeFile ) = @_;

    my @opts;
    if ( $msg =~ /\(([\w\|]+)\)$/ ) {
        my $optLine = $1;
        @opts = split( /\|/, $optLine );
    }

    my $role = $ENV{DECIDE_WITH_ROLE};
    my ( $userId, $enter ) = doInteract(
        $pipeFile,
        message => $msg,
        title   => 'Choose the action',
        opType  => 'button',
        role    => $role,
        options => \@opts
    );

    return ( $userId, $enter );
}

sub decideContinue {
    my ( $msg, $pipeFile, $logFH ) = @_;

    my $role = $ENV{DECIDE_WITH_ROLE};
    my ( $userId, $enter ) = doInteract(
        $pipeFile,
        message => $msg,
        title   => '',
        opType  => 'button',
        role    => $role,
        options => [ 'Yes', 'No' ]
    );

    my $isYes = 0;

    if    ( $enter =~ /\s*y\s*/i )   { $isYes = 1; }
    elsif ( $enter =~ /\s*yes\s*/i ) { $isYes = 1; }

    return $isYes;
}

sub initENV {
    my ( $envFile, $progname ) = @_;
    my $fh = new IO::File("<$envFile");
    if ( defined($fh) ) {
        my ( $line, $envName, $envValue );
        while ( $line = <$fh> ) {
            if ( $line =~ /([^\s]+?)\s*=\s*([^\s]+)/ ) {
                $envName  = $1;
                $envValue = $2;
                if ( not $envName =~ /^#/ ) {
                    if ( not $envName =~ /\./ ) {
                        $ENV{$envName} = $envValue;
                    }
                    elsif ( $envName =~ /^$progname\.(.+)/i ) {
                        $envName = $1;
                        $ENV{$envName} = $envValue;
                    }
                }
            }
        }
        $fh->close();
    }
    else {
        print STDERR ("ERROR: Cant not open env file:$envFile\n");
    }
}

sub setErrFlag {
    my ($val) = @_;
    if ( not defined($val) ) {
        $ENV{AUTOEXEC_FAIL_FLAG} = -1;
    }
    else {
        $ENV{AUTOEXEC_FAIL_FLAG} = $val;
    }
}

sub exitWithFlag {
    my $flag = $ENV{AUTOEXEC_FAIL_FLAG};
    exit($flag) if ( defined($flag) and $flag ne 0 );
}

sub getErrFlag {
    my $flag = $ENV{AUTOEXEC_FAIL_FLAG};
    return int($flag) if ( defined($flag) );
    return 0          if ( not defined($flag) );
}

sub guessEncoding {
    my ($file) = @_;

    #my $possibleEncodingConf = getSysConf('file.possible.encodings');
    my $possibleEncodingConf = '';

    my @possibleEncodings = ( 'GBK', 'UTF-8' );
    if ( defined($possibleEncodingConf) and $possibleEncodingConf ne '' ) {
        @possibleEncodings = split( /\s*,\s*/, $possibleEncodingConf );
    }

    my $encoding;
    my $charSet;

    my $fh = new IO::File("<$file");
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            my $enc = guess_encoding( $line, @possibleEncodings );
            if ( ref($enc) and $enc->mime_name ne 'US-ASCII' ) {
                $charSet = $enc->mime_name;
                last;
            }
        }
        $fh->close();
    }

    if ( not defined($charSet) ) {
        $charSet = `file -b --mime-encoding "$file"`;
        $charSet =~ s/^\s*|\s*$//g;
        $charSet = uc($charSet);
        if ( $charSet =~ /ERROR:/ or $charSet eq 'US-ASCII' or $charSet eq 'BINARY' ) {
            undef($charSet);
        }

        if ( not defined($charSet) ) {
            $charSet = $possibleEncodings[0];
        }
    }

    return $charSet;
}

sub guessDataEncoding {
    my ($data) = @_;

    #my $possibleEncodingConf = getSysConf('file.possible.encodings');
    my $possibleEncodingConf = '';

    my @possibleEncodings = ( 'GBK', 'UTF-8' );
    if ( defined($possibleEncodingConf) and $possibleEncodingConf ne '' ) {
        @possibleEncodings = split( /\s*,\s*/, $possibleEncodingConf );
    }

    my $encoding;
    my $charSet;

    foreach $encoding (@possibleEncodings) {
        my $enc = guess_encoding( $data, $encoding );
        if ( ref($enc) and $enc->mime_name ne 'US-ASCII' ) {
            $charSet = $enc->mime_name;
            last;
        }
    }

    if ( not defined($charSet) ) {
        $charSet = $possibleEncodings[0];
    }

    return $charSet;
}

sub setEnv {
    use IO::Handle;
    STDOUT->autoflush(1);
    STDERR->autoflush(1);
    my $techsureHome = $ENV{TECHSURE_HOME};
    if ( not defined($techsureHome) or $techsureHome eq '' ) {
        $techsureHome = Cwd::abs_path("$FindBin::Bin/../..");
    }
    my $deploysysHome;
    if ( exists $ENV{DEPLOYSYS_HOME} ) {
        $deploysysHome = $ENV{DEPLOYSYS_HOME};
    }
    else {
        $deploysysHome = Cwd::abs_path("$FindBin::Bin/..");
    }

    $ENV{HOME}           = $deploysysHome;
    $ENV{DEPLOYSYS_HOME} = $deploysysHome;
    $ENV{USER}           = `whoami`;
    $ENV{LANG}           = 'en_US.UTF-8';
    $ENV{LC_ALL}         = 'en_US.UTF-8';
    $ENV{NLS_LANG}       = 'AMERICAN_AMERICA.AL32UTF8';
    $ENV{TERM}           = 'dumb';
    $ENV{JAVA_HOME}      = "$techsureHome/serverware/jdk";

    #$ENV{MAVEN_OPTS}      = '-XX:MaxPermSize=256M';
    #$ENV{ORACLE_HOME}     = "$deploysysHome/tools/oracle/instantclient_12_1";
    #$ENV{DB2_HOME}        = "$deploysysHome/tools/db2/sqllib";
    #$ENV{LD_LIBRARY_PATH} = $ENV{ORACLE_HOME} . ':' . $ENV{ORACLE_HOME} . '/lib:' . $ENV{ORACLE_HOME} . '/bin' . ":$techsureHome/serverware/git/lib64";
    $ENV{PATH} = "$deploysysHome/bin:"

        #. "$techsureHome/serverware/ant/bin:"
        #. "$techsureHome/serverware/maven/bin:"
        #. "$techsureHome/serverware/gradle/bin:"
        . "$techsureHome/serverware/jdk/bin:" . "/bin:/usr/bin:/usr/local/bin:"

        #. "$techsureHome/serverware/git/bin:"
        #. $ENV{ORACLE_HOME} . ':'
        #. $ENV{ORACLE_HOME} . '/bin:'
        #. $ENV{ORACLE_HOME} . '/lib:'
        #. $ENV{DB2_HOME} . '/bin:'
        . $ENV{PATH};

    #$ENV{M2_HOME}  = "$techsureHome/serverware/maven";
    #$ENV{ANT_HOME} = "$techsureHome/serverware/ant";
    #
    $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
}

sub getFileContent {
    my ($filePath) = @_;
    my $content;

    if ( -f $filePath ) {
        my $size = -s $filePath;
        my $fh   = new IO::File("<$filePath");

        if ( defined($fh) ) {
            $fh->read( $content, $size );
            $fh->close();
        }
        else {
            print("WARN: File:$filePath not found or can not be readed.\n");
        }
    }

    return $content;
}

1;

