#!/usr/bin/perl
use strict;

package DeployUtils;
use feature 'state';
use Cwd;
use Crypt::RC4;
use Encode;
use Encode::Guess;
use JSON;
use File::Find;
use File::Path;
use File::Copy;

use ServerConf;
use ServerAdapter;
use AutoExecUtils;

our $TERM_CHARSET;
our $READ_TMOUT = 86400;

sub new {
    my ($pkg) = @_;

    state $instance;
    if ( !defined($instance) ) {
        my $self = {};
        $instance = bless( $self, $pkg );

        $self->{serverConf} = ServerConf->new();
    }

    return $instance;
}

sub deployInit {
    my ( $self, $namePath, $version, $buildNo ) = @_;

    AutoExecUtils::setEnv();

    my $dpPath          = $ENV{_DEPLOY_PATH};
    my $dpIdPath        = $ENV{_DEPLOY_ID_PATH};
    my $deployConf      = $ENV{_DEPLOY_CONF};
    my $runnerGroupConf = $ENV{_DEPLOY_RUNNERGROUP};
    my $buildNo         = $ENV{BUILD_NO};
    my $isRelease       = $ENV{IS_RELEASE};

    if ( not defined($isRelease) or $isRelease eq '' ) {
        $isRelease = 0;
    }
    else {
        $isRelease = int($isRelease);
    }

    my $deployEnv = {};
    $deployEnv->{JOB_ID}     = $ENV{AUTOEXEC_JOBID};
    $deployEnv->{RUNNER_ID}  = $ENV{RUNNER_ID};
    $deployEnv->{_SQL_FILES} = $ENV{_SQL_FILES};
    $deployEnv->{BUILD_NO}   = $buildNo;
    $deployEnv->{IS_RELEASE} = $isRelease;

    if ( defined($deployConf) and $deployConf ne '' ) {
        $deployEnv->{DEPLOY_CONF} = from_json($deployConf);
    }
    if ( defined($runnerGroupConf) and $runnerGroupConf ne '' ) {
        $deployEnv->{RUNNER_GROUP} = from_json($runnerGroupConf);
    }

    if ( defined($namePath) and $namePath ne '' and uc($namePath) ne 'DEFAULT' ) {
        my $idPath = ServerAdapter->getIdPath($namePath);
        $dpPath               = $namePath;
        $dpIdPath             = $idPath;
        $ENV{_DEPLOY_PATH}    = $dpPath;
        $ENV{_DEPLOY_ID_PATH} = $dpIdPath;
    }

    my @dpNames = split( '/', $dpPath );
    my @dpIds   = split( '/', $dpIdPath );

    my $idx = 0;
    for my $level ( 'SYS', 'MODULE', 'ENV' ) {
        $ENV{ $level . "_ID" }           = $dpIds[$idx];
        $ENV{ $level . "_NAME" }         = $dpNames[$idx];
        $deployEnv->{ $level . "_ID" }   = $dpIds[$idx];
        $deployEnv->{ $level . "_NAME" } = $dpNames[$idx];
        $idx                             = $idx + 1;
    }

    my $autoexecHome = $ENV{AUTOEXEC_HOME};
    if ( not defined($autoexecHome) or $autoexecHome eq '' ) {
        $autoexecHome = Cwd::realpath("$FindBin::Bin/../../..");
        my $toolsPath = "$autoexecHome/tools";
        $ENV{AUTOEXEC_HOME}         = $autoexecHome;
        $ENV{TOOLS_PATH}            = $toolsPath;
        $deployEnv->{AUTOEXEC_HOME} = $autoexecHome;
        $deployEnv->{TOOLS_PATH}    = $toolsPath;
    }
    my $dataPath = "$autoexecHome/data/verdata/$ENV{SYS_ID}/$ENV{MODULE_ID}";
    $ENV{_DEPLOY_DATA_PATH} = $dataPath;
    my $prjPath = "$dataPath/workspace/project";
    $ENV{_DEPLOY_PRJ_PATH} = $prjPath;

    if ( defined($version) and $version ne '' ) {
        $ENV{VERSION} = $version;
    }
    else {
        $version = $ENV{VERSION};
    }

    my $buildRoot = "$dataPath/artifact/$version/build";
    my $buildPath = "$buildRoot/$buildNo";

    $deployEnv->{VERSION}    = $version;
    $deployEnv->{BUILD_ROOT} = $buildRoot;
    $deployEnv->{BUILD_PATH} = $buildPath;
    $deployEnv->{ID_PATH}    = $dpIdPath;
    $deployEnv->{NAME_PATH}  = $dpPath;
    $deployEnv->{DATA_PATH}  = $dataPath;
    $deployEnv->{PRJ_PATH}   = $prjPath;

    return $deployEnv;
}

sub getDataDirStruct {
    my ( $self, $buildEnv, $isRelative ) = @_;

    my $dataPath = $buildEnv->{DATA_PATH};
    my $envName  = $buildEnv->{ENV_NAME};
    my $version  = $buildEnv->{VERSION};
    my $buildNo  = $buildEnv->{BUILD_NO};

    my $workSpacePath = "workspace";
    my $prjPath       = "$workSpacePath/project";
    my $verRoot       = "artifact/$version";
    my $relRoot       = "$verRoot/build";
    my $relPath       = "$relRoot/$buildNo";
    my $distPath      = "$verRoot/env/$envName";
    my $mirrorPath    = "mirror/$envName";
    my $envresPath    = "envres/$envName";

    my $dirStructure = {};
    if ( $isRelative == 1 ) {
        $dirStructure = {
            approot     => $dataPath,
            workspace   => $workSpacePath,
            verroot     => $verRoot,
            project     => $prjPath,
            release     => $relPath,
            releaseRoot => $relRoot,
            distribute  => $distPath,
            mirror      => $mirrorPath,
            envres      => $envresPath
        };
    }
    else {
        $dirStructure = {
            approot     => $dataPath,
            workspace   => "$dataPath/$workSpacePath",
            verroot     => "$dataPath/$verRoot",
            project     => "$dataPath/$prjPath",
            release     => "$dataPath/$relPath",
            releaseRoot => "$dataPath/$relRoot",
            distribute  => "$dataPath/$distPath",
            mirror      => "$dataPath/$mirrorPath",
            envres      => "$dataPath/$envresPath"
        };
    }

    return $dirStructure;
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

sub decryptPwd {
    my ( $self, $data ) = @_;
    return $self->{serverConf}->decryptPwd($data);
}

sub getFileContent {
    my ( $self, $filePath ) = @_;
    my $content;

    if ( -f $filePath ) {
        my $size = -s $filePath;
        my $fh   = new IO::File("<$filePath");

        if ( defined($fh) ) {
            $fh->read( $content, $size );
            $fh->close();
        }
        else {
            print("WARN: file:$filePath not found or can not be readed.\n");
        }
    }

    return $content;
}

sub getScriptExtName {
    my ( $self, $interpreter ) = @_;

    my $type2ExtName = {
        perl       => '.pl',
        python     => '.py',
        ruby       => '.rb',
        cmd        => '.bat',
        powershell => '.ps1',
        vbscript   => '.vbs',
        bash       => '.sh',
        ksh        => '.sh',
        csh        => '.sh',
        sh         => '.sh',
        javascript => '.js'
    };

    return $type2ExtName->{$interpreter};
}

sub execmd {
    my ( $self, $cmd, $pattern ) = @_;
    my $encoding;
    my $lang = $ENV{LANG};

    if ( not defined($lang) or $lang eq '' ) {
        $ENV{LANG} = 'en_US.UTF-8';
        $encoding = 'utf-8';
    }
    else {
        $encoding = lc( substr( $lang, rindex( $lang, '.' ) + 1 ) );
        $encoding = 'utf-8' if ( $encoding eq 'utf8' );
    }

    my $exitCode = -1;
    my ( $pid, $handle );
    if ( $pid = open( $handle, "$cmd 2>\&1 |" ) ) {
        my $line;
        if ( $encoding eq 'utf-8' ) {
            while ( $line = <$handle> ) {
                if ( defined($pattern) ) {
                    $line =~ s/$pattern//;
                }

                print($line);
            }
        }
        else {
            while ( $line = <$handle> ) {
                if ( defined($pattern) ) {
                    $line =~ s/$pattern//;
                }
                print( Encode::encode( "utf-8", Encode::decode( $encoding, $line ) ) );
            }
        }

        waitpid( $pid, 0 );
        $exitCode = $?;

        if ( $exitCode > 255 ) {
            $exitCode = $exitCode >> 8;
        }

        close($handle);
    }

    return $exitCode;
}

#读取命令执行后管道的输出
sub getPipeOut {
    my ( $self, $cmd, $isVerbose ) = @_;
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
        die("ERROR: execute '$cmd' failed.\n");
    }

    return \@outArray;
}

#读取命令执行后管道的输出
sub teePipeOut {
    my ( $self, $cmd ) = @_;
    return getPipeOut( $cmd, 1 );
}

#读取命令执行后管道的输出
sub handlePipeOut {
    my ( $self, $cmd, $callback, $isVerbose, $execDesc ) = @_;

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
            die("ERROR: execute '$execDesc' failed.\n");
        }
        else {
            die("ERROR: execute '$cmd' failed.\n");
        }
    }

    return $exitCode;
}

sub copyTree {
    my ( $self, $src, $dest ) = @_;

    if ( not -d $src ) {
        my $dir = dirname($dest);
        mkpath($dir) if ( not -e $dir );
        copy( $src, $dest ) || die("ERROR: copy $src to $dest failed:$!");
        chmod( ( stat($src) )[2], $dest );
    }
    else {
        #$dest = Cwd::abs_path($dest);
        my $cwd = getcwd();
        chdir($src);

        find(
            {
                wanted => sub {
                    my $fileName  = $File::Find::name;
                    my $targetDir = "$dest/$File::Find::dir";
                    mkpath($targetDir) if not -e $targetDir;

                    my $srcFile = $_;
                    if ( -f $srcFile ) {

                        #print("copy $_ $dest/$fileName\n");
                        my $destFile = "$dest/$fileName";
                        copy( $srcFile, $destFile ) || die("ERROR: copy $srcFile to $destFile failed:$!");
                        chmod( ( stat($srcFile) )[2], $destFile );
                    }
                },
                follow => 0
            },
            '.'
        );

        chdir($cwd);
    }
}

sub getMonth {
    my ( $self, $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $nowMon = sprintf( '%4d%02d', $year + 1900, $mon + 1 );

    return $nowMon;
}

sub getDate {
    my ( $self, $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $nowdate = sprintf( '%4d%02d%02d', $year + 1900, $mon + 1, $mday );

    return $nowdate;
}

sub getTimeStr {
    my ( $self, $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $timeStr = sprintf( '%4d%02d%02d_%02d%02d%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

    return $timeStr;
}

sub getTimeForLog {
    my ( $self, $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $timeStr = sprintf( '[%02d:%02d:%02d]', $hour, $min, $sec );

    return $timeStr;
}

sub getDateTimeForLog {
    my ( $self, $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $timeStr = sprintf( '[%4d-%02d-%02d %02d:%02d:%02d]', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

    return $timeStr;
}

sub escapeQuote {
    my ( $self, $line ) = @_;
    $line =~ s/([\{\}\(\)\[\]\'\"\$\s\&\!])/\\$1/g;
    return $line;
}

sub escapeQuoteWindows {
    my ( $self, $line ) = @_;
    $line =~ s/([\'\"\$\&\^\%])/^$1/g;
    return $line;
}

sub convToUTF8 {
    my ( $self, $content ) = @_;
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

sub charsetConv {
    my ( $self, $content, $from ) = @_;

    my $encoding;
    my $lang = $ENV{LANG};
    if ( not defined($lang) or $lang eq '' ) {
        $ENV{LANG} = 'en_US.UTF-8';
        $encoding = 'utf-8';
    }
    else {
        $encoding = lc( substr( $lang, rindex( $lang, '.' ) + 1 ) );
        $encoding = 'utf-8' if ( $encoding eq 'utf8' );
    }

    if ( $from ne $encoding ) {
        $content = Encode::encode( $encoding, Encode::decode( $from, $content ) );
    }
    return $content;
}

sub guessEncoding {
    my ( $self, $file ) = @_;

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
    my ( $self, $data ) = @_;

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

sub doInteract {
    my ( $self, $pipeFile, %args ) = @_;

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
                print("\nWARN:wait user input timeout.\n");
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
    my ( $self, $msg, $pipeFile, $role ) = @_;

    my @opts;
    if ( $msg =~ /\(([\w\|]+)\)$/ ) {
        my $optLine = $1;
        @opts = split( /\|/, $optLine );
    }

    my ( $userId, $enter ) = $self->doInteract(
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
    my ( $self, $msg, $pipeFile, $role ) = @_;

    my ( $userId, $enter ) = $self->doInteract(
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

sub url_encode {
    my ( $self, $rv ) = @_;
    $rv =~ s/([^a-z\d\Q.-_~ \E])/sprintf("%%%2.2X", ord($1))/geix;
    $rv =~ tr/ /+/;
    return $rv;
}

sub url_decode {
    my ( $self, $rv ) = @_;
    $rv =~ tr/+/ /;
    $rv =~ s/\%([a-f\d]{2})/ pack 'C', hex $1 /geix;
    return $rv;
}
1;
