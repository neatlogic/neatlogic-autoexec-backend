#!/usr/bin/perl
use FindBin;

use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

package Utils;

use strict;
use POSIX;
use IO::Socket;
use IO::Socket::SSL;
use IO::File;
use Sys::Hostname;
use File::Copy;
use File::Find;
use File::Path;
use Term::ReadKey;
use Encode;
use Encode::Guess;
use CharsetDetector;
use File::Basename;
use Cwd;
use File::Glob qw(bsd_glob);
use CommonConfig;
use ENVPathInfo;
use ServerAdapter;
use VerNotice;

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

sub charsetConv {
    my ( $content, $from ) = @_;

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

sub execmd {
    my ( $cmd, $pattern ) = @_;
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
    my $pid = open( PIPE, "$cmd |" );
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
            die("ERROR: execute '$execDesc' failed.\n");
        }
        else {
            die("ERROR: execute '$cmd' failed.\n");
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
            }
    }
}

#获取指定目录里的所有文件列表
sub getFilesInDir {
    my ( $path, $fileList ) = @_;
    my $file     = '';
    my $filePath = '';
    my @entries  = ();

    if ( not defined($fileList) ) {
        my @fileListArray = ();
        $fileList = \@fileListArray;
    }

    if ( opendir( DIR, $path ) ) {
        @entries = readdir(DIR);
        closedir(DIR);

        foreach $file (@entries) {
            $filePath = "$path/$file";
            if ( -f $filePath ) {
                push( @$fileList, $filePath );
            }
            elsif ( $file ne '.' and $file ne '..' ) {
                Utils::getFilesInDir( $filePath, $fileList );
            }
        }
    }
    else {
        print STDERR ("ERROR: can not open directory:$path check permission.\n");
    }

    return $fileList;
}

#遍历指定目录中的所有文件，并逐个文件执行输入的函数
sub walkFilesInDir {
    my ( $path, $fileProc, @fileProcArgs ) = @_;
    my $file     = '';
    my $filePath = '';
    my @entries  = ();

    if ( opendir( DIR, $path ) ) {
        @entries = readdir(DIR);
        closedir(DIR);

        foreach $file (@entries) {
            $filePath = "$path/$file";
            if ( -f $filePath ) {
                &$fileProc( $filePath, @fileProcArgs );
            }
            elsif ( $file ne '.' and $file ne '..' ) {
                Utils::walkFilesInDir( $filePath, $fileProc, @fileProcArgs );
            }
        }
    }
    else {
        print STDERR ("ERROR: can not open directory:$path check permission.\n");
    }

    return;
}

#将文件拷贝到目标路径，如果目标路径不存在则创建
sub copyWithDir {
    my ( $srcDir, $destDir, $isverbose ) = @_;

    if ( -e $destDir and $isverbose ) {
        print("HINT: copy to:${destDir}\n");
    }

    #创建目录, 创建目录树中的各层目录
    my ( @dirs, $dirLen, $i );
    @dirs = split( /\/|\\/, $destDir );
    $dirLen = scalar(@dirs) - 1;

    my $dirStr = '';
    for ( $i = 0 ; $i < $dirLen ; $i++ ) {
        $dirStr = $dirStr . $dirs[$i];

        if ( !-e $dirStr ) {
            mkdir($dirStr);
        }
        $dirStr = $dirStr . '/';
    }

    #目录创建完成

    File::Copy::copy( $srcDir, $destDir );
    chmod( ( stat($srcDir) )[2], $destDir );
}

sub getHostIp {
    my ($host) = @_;

    my $hostIp = join( ".", unpack( "C4", gethostbyname($host) ) );
    if ( not defined($hostIp) or $hostIp eq '' ) {
        print STDERR ("ERROR: can not find the host ip.\n");
    }
    else {
        $host = $hostIp;
    }

    return $host;
}

sub getIPStr {
    my $host = Sys::Hostname::hostname();
    my ( $name, $aliases, $addrtype, $length, @addrs ) = gethostbyname($host);
    my ( $a, $b, $c, $d ) = unpack( 'C4', $addrs[0] );
    my $ip = "$a.$b.$c.$d";
    return $ip;
}

sub getMonth {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $nowMon = sprintf( '%4d%02d', $year + 1900, $mon + 1 );

    return $nowMon;
}

sub getDate {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $nowdate = sprintf( '%4d%02d%02d', $year + 1900, $mon + 1, $mday );

    return $nowdate;
}

sub getTimeStr {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $timeStr = sprintf( '%4d%02d%02d_%02d%02d%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

    return $timeStr;
}

sub getTimeForLog {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $timeStr = sprintf( '[%02d:%02d:%02d]', $hour, $min, $sec );

    return $timeStr;
}

sub getDateTimeForLog {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $timeStr = sprintf( '[%4d-%02d-%02d %02d:%02d:%02d]', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );

    return $timeStr;
}

sub decideOption {
    my ( $msg, $inputPipe, $logFH ) = @_;

    sigHandler(
        'TERM', 'INT', 'HUP', 'ABRT',
        sub {
            unlink($inputPipe) if ( -e $inputPipe );
            return -1;
        }
    );

    my $decideRole = $ENV{DECIDE_WITH_ROLE};
    if ( defined($decideRole) and $decideRole ne '' and $msg !~ /^\[.*?\]/ ) {
        $msg = "[$decideRole]$msg";
    }

    my $usePipe = 0;
    $usePipe = 1 if ( defined($inputPipe) and exists( $ENV{IS_INTERACT} ) and exists( $ENV{JOB_ID} ) );

    #print $logFH ("DEBUG: is interact:" . $ENV{IS_INTERACT} . ",use Pipe:$usePipe\n");

    my $enter  = '';
    my $userId = '';

    my $hasOpts = 0;
    my %options;
    if ( $msg =~ /\(([\w\|]+)\)$/ ) {
        my $optLine = $1;
        my @opts = split( /\|/, $1 );
        my $opt;

        foreach $opt (@opts) {
            if ( lc($opt) ne 'input' ) {
                $hasOpts = 1;
                $options{$opt} = 1;
            }
        }
    }

    $| = 1;
    my $cmdPrefix = '<Wait for instrunction>';

    my $scope    = $ENV{SCOPE};
    my $ticketId = $ENV{TICKET_ID};
    my $playbook = $ENV{PLAYBOOK};
    my $version  = $ENV{VERSION};
    my $subSys   = $ENV{SUBSYS};
    my $sys      = $ENV{SYS};
    my $env      = $ENV{ENV};

    eval {
        local $SIG{ALRM} = sub {
            print("\nWARN:wait user input timeout.\n");
            if ( defined($logFH) ) {
                print $logFH ("\nWARN:wait user input timeout.\n");
            }
            $enter = 'force-exit';
            die("Read time out");
        };
        alarm($READ_TMOUT);

        if ( defined($ticketId) and defined($playbook) and defined($version) and defined($subSys) ) {
            ServerAdapter::callback( 'waitinput', $scope, $ticketId, $playbook, '', $sys, $subSys, $version, $env );

            #send waitinput notice
            my $jobId      = $ENV{JOB_ID};
            my $envPath    = $ENV{ENVPATH};
            my $subSysPath = $ENV{SUBSYSPATH};
            if ( not defined($envPath) or $envPath eq '' ) {
                $envPath = $subSysPath;
            }
            my $envInfo = ENVPathInfo::parse( $envPath, $version );
            my $verNotice = VerNotice->new( $envInfo, $version, $playbook, 2, $ticketId, $jobId );
            $verNotice->notice();
        }

        print("\n$cmdPrefix$msg:\n");

        if ( defined($logFH) ) {
            print $logFH ("\n$cmdPrefix$msg:");
            $logFH->flush();
        }

        #$enter = Term::ReadKey::ReadLine(0);
        if ( $usePipe eq 0 ) {
            $enter = <STDIN>;
        }
        else {
            $enter = 'force-exit';
            my $ticket = $ENV{TICKET_ID};
            if ( defined($ticket) ) {
                unlink($inputPipe) if ( -e $inputPipe );
                POSIX::mkfifo( $inputPipe, 0700 );

                my $pipe = IO::File->new("<$inputPipe");
                if ( defined($pipe) ) {
                    $enter = $pipe->getline();
                    $enter = 'force-exit' if ( not defined($enter) );
                    print("\n");
                    if ( defined($logFH) ) {
                        print $logFH ("\n");
                    }
                    $pipe->close();
                }
                unlink($inputPipe) if ( -e $inputPipe );
            }
        }
        alarm(0);
    };

    $enter =~ s/\s*$//;
    if ( $enter =~ /^\[(.*?)\]# (.*)$/ ) {
        $userId = $1;
        $enter  = $2;
    }

    while ( $hasOpts == 1 and not $options{$enter} eq 1 and $enter ne 'force-exit' ) {
        print("\n$cmdPrefix incorrect input, try again. $msg:");
        if ( defined($logFH) ) {
            print $logFH ("\n$cmdPrefix incorrect input, try again. $msg:");
        }
        eval {
            local $SIG{ALRM} = sub {
                print("\nWARN:wait user input timeout.\n");
                if ( defined($logFH) ) {
                    print $logFH ("\nWARN:wait user input timeout.\n");
                }
                $enter = 'force-exit';
                die("Read time out");
            };
            alarm($READ_TMOUT);

            #$enter = Term::ReadKey::ReadLine(0);
            if ( $usePipe eq 0 ) {
                $enter = <STDIN>;
            }
            else {
                $enter = 'force-exit';
                my $ticket = $ENV{TICKET_ID};
                if ( defined($ticket) ) {
                    unlink($inputPipe) if ( -e $inputPipe );
                    POSIX::mkfifo( $inputPipe, 0700 );

                    my $pipe = IO::File->new("<$inputPipe");
                    if ( defined($pipe) ) {
                        $enter = $pipe->getline();
                        if ( not defined($enter) ) {
                            $enter = 'force-exit';
                            last;
                        }
                        print("\n");
                        if ( defined($logFH) ) {
                            print $logFH ("\n");
                        }
                        $pipe->close();
                    }
                    unlink($inputPipe) if ( -e $inputPipe );
                }
            }

            alarm(0);
        };
        $enter =~ s/\s*$//;
        if ( $enter =~ /^\[(.*?)\]# (.*)$/ ) {
            $userId = $1;
            $enter  = $2;
        }
    }

    undef($enter) if ( $enter eq 'force-exit' );
    if ( defined($logFH) ) {
        print $logFH ("$enter\n");
    }

    unlink($inputPipe) if ( -e $inputPipe );

    if ( defined($ticketId) and defined($playbook) and defined($version) and defined($subSys) ) {
        ServerAdapter::callback( 'running', $scope, $ticketId, $playbook, '', $sys, $subSys, $version, $env );
    }

    return ( $userId, $enter );
}

sub decideContinue {
    my ( $msg, $inputPipe, $logFH ) = @_;

    my $msg   = "$msg(yes|no)";
    my $isYes = 0;

    my $enter = decideOption( $msg, $inputPipe, $logFH );
    if    ( $enter =~ /\s*y\s*/i )   { $isYes = 1 }
    elsif ( $enter =~ /\s*yes\s*/i ) { $isYes = 1 }

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
        print STDERR ("ERROR: cant not open env file:$envFile\n");
    }
}

sub readPass {
    my ($prompt) = @_;
    my $orgSignalHandler = $SIG{INT};

    $SIG{INT} = sub { Term::ReadKey::ReadMode('normal'); print("\n"); exit(-1); };

    print("$prompt:");
    Term::ReadKey::ReadMode('noecho');
    my $password;
    eval {
        local $SIG{ALRM} = sub { print("\nWARN:wait user input timeout.\n"); die("Read time out"); };
        alarm($READ_TMOUT);
        $password = Term::ReadKey::ReadLine(0);
        alarm(0);
    };
    Term::ReadKey::ReadMode('normal');
    chomp($password);
    print("\n");

    $SIG{INT} = $orgSignalHandler;

    return $password;
}

sub getProcCmdLine {
    my ($pid) = @_;
    my ( $procCmdFile, $cmdlineFH, $cmdline );
    $procCmdFile = "/proc/$pid/cmdline";
    if ( -e $procCmdFile ) {
        $cmdlineFH = new IO::File("<$procCmdFile");
        if ( defined($cmdlineFH) ) {
            $cmdline = <$cmdlineFH>;
            $cmdlineFH->close();
        }
    }

    return $cmdline;
}

sub getDeployPwd {
    my $pwdPath = "$FindBin::Bin/../conf/system/deploy.pwd";

    my $deployPwd = '';

    if ( -e $pwdPath ) {
        my $fh = IO::File->new("<$pwdPath");
        if ($fh) {
            $deployPwd = <$fh>;
            $fh->close();
        }
    }
    else {
        my $fh = IO::File->new("<$pwdPath.s");
        if ($fh) {
            $deployPwd = <$fh>;
            $fh->close();
        }

        $deployPwd =~ s/\s*$//;
        $fh = IO::File->new("<$pwdPath.e");
        if ($fh) {
            my $eDeployPwd = <$fh>;
            $deployPwd = $deployPwd . $eDeployPwd;
            $fh->close();
        }
    }

    $deployPwd =~ s/\s*$//;
    return $deployPwd;
}

sub setDeployPwd {
    my ($pass) = @_;
    my $pwdPath = "$FindBin::Bin/../conf/system/deploy.pwd";

    if ( -e $pwdPath ) {
        my $fh = IO::File->new(">$pwdPath");
        if ($fh) {
            print $fh ($pass);
            $fh->close();
        }
    }
    else {
        my $len   = $pass;
        my $sLen  = int( $pass / 2 );
        my $sPass = substr( $pass, 0, $sLen );
        my $ePass = substr( $pass, $sLen );

        my $fh = IO::File->new(">$pwdPath.s");
        if ($fh) {
            print $fh ($sPass);
            $fh->close();
        }

        $fh = IO::File->new(">$pwdPath.e");
        if ($fh) {
            print $fh ($ePass);
            $fh->close();
        }
    }
}

sub getPass {
    my ( $pType, $target, $user, $env ) = @_;
    my $pass;

    use CredentialAdmin;
    my $credPath  = "$FindBin::Bin/../conf/";
    my $credAdmin = CredentialAdmin->new($credPath);
    my $deployPwd = getDeployPwd();

    eval { $pass = $credAdmin->getPwd( $deployPwd, $pType, "$target\:\:$user", $env ); };

    if ( not defined($pass) or $pass eq '' ) {
        die("ERROR: Can not find password for $user\@$target.\n");
    }

    return $pass;
}

sub setErrFlag {
    my ($val) = @_;
    if ( not defined($val) ) {
        $ENV{easydplyrunflag} = -1;
    }
    else {
        $ENV{easydplyrunflag} = $val;
    }
}

sub exitWithFlag {
    my $flag = $ENV{easydplyrunflag};
    exit($flag) if ( defined($flag) and $flag ne 0 );
}

sub getErrFlag {
    my $flag = $ENV{easydplyrunflag};
    return int($flag) if ( defined($flag) );
    return 0 if ( not defined($flag) );
}

sub getPrjResRoot {
    my ($prjSrc) = @_;
    my $prjResRoot = $prjSrc;

    if ( -d "$prjSrc/db" or -d "$prjSrc/doc" ) {
        $prjResRoot = $prjSrc;
    }
    else {
        my @subPoms = bsd_glob("$prjSrc/*");

        for my $subDir (@subPoms) {
            if ( -d "$prjSrc/db" or -d "$prjSrc/doc" ) {
                $prjResRoot = $subDir;
                last;
            }
        }
    }

    return $prjResRoot;
}

sub getPrjRoots {
    my ($prjSrc) = @_;
    my @prjRoots;

    if ( -f "$prjSrc/pom.xml" or -f "$prjSrc/build.xml" or -f "$prjSrc/build.gradle" ) {
        push( @prjRoots, $prjSrc );
    }
    else {
        my @subPoms = bsd_glob("$prjSrc/*");

        for my $subDir (@subPoms) {
            if ( -f "$subDir/pom.xml" or -f "$subDir/build.xml" or -f "$subDir/build.gradle" ) {
                push( @prjRoots, $subDir );
            }
        }
    }

    push( @prjRoots, $prjSrc ) if ( scalar(@prjRoots) == 0 );

    return @prjRoots;
}

sub getPrjDir {
    my ($subSysInfo) = @_;

    my $prjSrc = $subSysInfo->{prjsrc};

    #if ( -e "$prjSrc.buildinenv" ) {
    #    my $envName = $ENV{ENVNAME};
    #    if ( not defined($envName) or $envName eq '' ) {
    #        $envName = $subSysInfo->{defaultenvname};
    #    }
    #    if ( not defined($envName) or $envName eq '' ) {
    #        my $fh = new IO::File("<$prjSrc.buildinenv");
    #        if ( defined($fh) ) {
    #            $envName = <$fh>;
    #            $fh->close();
    #        }
    #    }
    #
    #    if ( not -e $prjSrc ) {
    #        mkpath($prjSrc);
    #    }
    #
    #    $prjSrc = "$prjSrc/$envName";
    #}

    return $prjSrc;
}

sub getAppbuildDir {
    my ($subSysInfo) = @_;

    my $prjSrc      = $subSysInfo->{prjsrc};
    my $appbuildDir = $subSysInfo->{buildsrc};

    #if ( -e "$prjSrc.buildinenv" ) {
    #    my $envName = $ENV{ENVNAME};
    #    if ( not defined($envName) or $envName eq '' ) {
    #        $envName = $subSysInfo->{defaultenvname};
    #    }
    #    if ( not defined($envName) or $envName eq '' ) {
    #        my $fh = new IO::File("<$prjSrc.buildinenv");
    #        if ( defined($fh) ) {
    #            $envName = <$fh>;
    #            $fh->close();
    #        }
    #    }
    #
    #    $appbuildDir = "$appbuildDir/$envName";
    #    if ( not -e $appbuildDir ) {
    #        mkpath($appbuildDir);
    #    }
    #}

    return $appbuildDir;
}

sub guessEncoding {
    my ($file) = @_;

    my $possibleEncodingConf = getSysConf('file.possible.encodings');

    my @possibleEncodings = ( 'GBK', 'UTF-8' );
    if ( defined($possibleEncodingConf) and $possibleEncodingConf ne '' ) {
        @possibleEncodings = split( /\s*,\s*/, $possibleEncodingConf );
    }

    my $encoding;
    my $charSet;

    my $fh = new IO::File("<$file");
    if ( defined($fh) ) {
        my $lineCount = 0;
        my $line;
        while ( $line = $fh->getline() ) {
            $lineCount++;
            my $enc = guess_encoding( $line, @possibleEncodings );
            if ( ref($enc) ) {
                if ( $enc->mime_name ne 'US-ASCII' ) {
                    $charSet = $enc->mime_name;
                    last;
                }
            }
            else {
                if ( $enc eq 'utf-8-strict or utf8' ) {
                    $charSet = 'UTF-8';
                    last;
                }
                elsif ( $enc !~ /ascii/i and $enc !~ /iso/i ) {
                    foreach my $pEnc (@possibleEncodings) {
                        eval {
                            my $destTmp = Encode::encode( 'UTF-8', Encode::decode( $pEnc,   $line ) );
                            my $srcTmp  = Encode::encode( $pEnc,   Encode::decode( 'UTF-8', $destTmp ) );
                            if ( $srcTmp eq $line ) {
                                $charSet = $pEnc;
                                last;
                            }
                        };
                    }
                    if ( defined($charSet) ) {
                        last;
                    }
                }
            }
        }
        $fh->close();

        if ( $lineCount == 0 ) {
            $charSet = $possibleEncodings[0];
        }
    }

    if ( not defined($charSet) ) {
        $charSet = `file -b --mime-encoding '$file'`;
        $charSet =~ s/^\s*|\s*$//g;
        $charSet = uc($charSet);
        if ( $charSet =~ /ERROR:/ or $charSet eq 'BINARY' ) {
            undef($charSet);
        }

        #if ( $charSet eq 'US-ASCII' ) {
        if ( $charSet eq 'US-ASCII' or $charSet eq 'ISO-8859-1' ) {
            $charSet = $possibleEncodings[0];
        }
    }

    return $charSet;
}

sub guessDataEncoding {
    my ($data) = @_;

    my $possibleEncodingConf = getSysConf('file.possible.encodings');

    my @possibleEncodings = ( 'GBK', 'UTF-8' );
    if ( defined($possibleEncodingConf) and $possibleEncodingConf ne '' ) {
        @possibleEncodings = split( /\s*,\s*/, $possibleEncodingConf );
    }

    my $encoding;
    my $charSet;

    foreach $encoding (@possibleEncodings) {
        my $enc = guess_encoding( $data, $encoding );
        if ( ref($enc) ) {
            if ( $enc->mime_name ne 'US-ASCII' ) {
                $charSet = $enc->mime_name;
                last;
            }
        }
        else {
            if ( $enc eq 'utf-8-strict or utf8' ) {
                $charSet = 'UTF-8';
                last;
            }
            elsif ( $enc !~ /ascii/i and $enc !~ /iso/i ) {
                foreach my $pEnc (@possibleEncodings) {
                    eval {
                        my $destTmp = Encode::encode( 'UTF-8', Encode::decode( $pEnc,   $data ) );
                        my $srcTmp  = Encode::encode( $pEnc,   Encode::decode( 'UTF-8', $destTmp ) );
                        if ( $srcTmp eq $data ) {
                            $charSet = $pEnc;
                            last;
                        }
                    };
                }
                if ( defined($charSet) ) {
                    last;
                }
            }
        }
    }

    if ( not defined($charSet) ) {
        $charSet = $possibleEncodings[0];
    }

    return $charSet;
}

#sub isFileUtf8Encoding {
#    my ($file) = @_;
#
#    my $isUtf8 = 0;
#    my $size   = -s $file;
#    my $fh     = new IO::File("<$file");
#
#    if ( defined($fh) ) {
#        my $content;
#
#        $fh->read( $content, $size );
#        my $charSet = CharsetDetector::detect($content);
#        $fh->close();
#
#        $isUtf8 = 1 if ( $charSet eq 'utf8' );
#    }
#    return $isUtf8;
#}

sub copyTree {
    my ( $src, $dest ) = @_;

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

sub getSysConf {
    my ($confKey) = @_;
    if ( not defined($SYSTEM_CONF) ) {
        my $sysConfPath = "$FindBin::Bin/../conf/system";
        $SYSTEM_CONF = new CommonConfig( $sysConfPath, 'system.conf' );
    }

    return $SYSTEM_CONF->getConfig($confKey);
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
    IO::Socket::SSL::set_defaults(
        'SSL_verify_mode'     => IO::Socket::SSL::SSL_VERIFY_NONE,
        'SSL_verify_callback' => sub { return 1; }
    );
}

sub clearVersion {
    my ( $versionsDir, $version ) = @_;

    return if ( not defined($version)     or $version eq "" );
    return if ( not defined($versionsDir) or $versionsDir eq "" );

    #remove build target rsources
    rmtree("$versionsDir/$version/appbuild") if ( -d "$versionsDir/$version/appbuild" );
}

sub delFileHeadingBytes {
    my ( $filePath, $bytesCount ) = @_;
    my $fhRead  = IO::File->new("+<$filePath");
    my $fhWrite = IO::File->new("+<$filePath");

    if ( defined($fhRead) and defined($fhWrite) ) {
        $fhRead->seek( $bytesCount, 0 );
        $fhWrite->seek( 0, 0 );

        my $buf;
        my $len      = 0;
        my $totalLen = 0;

        do {
            $len = $fhRead->sysread( $buf, 16 );
            $fhWrite->syswrite( $buf, $len );
            $totalLen = $totalLen + $len;
        } while ( $len > 0 );

        $fhRead->close();
        $fhWrite->truncate($totalLen);
        $fhWrite->close();
    }
    else {
        die("Open file:$filePath failed");
    }
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
            print("WARN: file:$filePath not found or can not be readed.\n");
        }
    }

    return $content;
}

1;

