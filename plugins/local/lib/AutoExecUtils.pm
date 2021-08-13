#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use POSIX;
use IO::Socket;
use IO::Socket::SSL;
use IO::Socket::UNIX;
use IO::Select;
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
use JSON qw(from_json to_json);

package AutoExecUtils;

use IO::File;
use JSON qw(to_json from_json);

my $READ_TMOUT = 86400;
my $TERM_CHARSET;

sub setEnv {
}

sub saveOutput {
    my ($outputData) = @_;
    my $outputPath = $ENV{OUTPUT_PATH};

    if ( defined($outputPath) and $outputPath ne '' ) {
        my $fh = IO::File->new(">$outputPath");
        if ( defined($fh) ) {
            print $fh ( to_json($outputData) );
            $fh->close();
        }
        else {
            die("ERROR: Can not open output file:$outputPath to write.\n");
        }
    }
}

sub getMyNode {
    my $nodeJson = $ENV{AUTOEXEC_NODE};
    my $node;

    if ( defined($nodeJson) and $nodeJson ne '' ) {
        $node = from_json($nodeJson);
    }

    return $node;
}

sub getNode {
    my ($nodeId) = @_;
    my $nodesJsonPath = $ENV{AUTOEXEC_NODES_PATH};

    my $node = {};
    my $fh   = IO::File->new("<$nodesJsonPath");
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            my $cNode = from_json($line);
            if ( $cNode->{nodeId} == $nodeId ) {
                $node = $cNode;
                last;
            }
        }
        $fh->close();
    }

    return $node;
}

sub getNodePipeFile {
    my ( $jobPath, $phaseName, $nodeInfo ) = @_;
    return "$jobPath/log/$phaseName/$nodeInfo->{host}-$nodeInfo->{port}-$nodeInfo->{resourceId}.txt.run.pipe";
}

sub doInteract {
    my (%args) = @_;

    my $pipeFile = $args{pipeFile};    # 管道文件的全路径
    my $message  = $args{message};     # 交互操作文案
    my $opType   = $args{opType};      # 类型：button|input|select|mselect
    my $title    = $args{title};       # 交互操作标题
    my $opts     = $args{options};     # 操作列表json数组，譬如：["commit","rollback"]
    my $role     = $args{role};        # 可以操作此操作的角色，如果空代表不控制

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

            my $select = IO::Select->new( $pipe, \*STDIN );
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

sub informNodeWaitInput {
    my (%args) = @_;

    # $args{nodeId}     #节点Id
    # $args{pipeFile};  # 管道文件的全路径
    # $args{message};    # 交互操作文案
    # $args{opType};     # 类型：button|input|select|mselect
    # $args{title};      # 交互操作标题
    # $args{options};    # 操作列表json数组，譬如：["commit","rollback"]
    # $args{role};       # 可以操作此操作的角色，如果空代表不控制

    my $sockPath = $ENV{AUTOEXEC_WORK_PATH} . '/job.sock';
    my $nodeId   = $args{nodeId};

    if ( -e $sockPath ) {
        eval {
            my $client = IO::Socket::UNIX->new(
                PeerAddr => $sockPath,
                Type     => IO::Socket::SOCK_DGRAM,
                Timeout  => 10
            );

            my $request = {};
            $request->{action} = 'informNodeWaitInput';
            $request->{nodeId} = $nodeId;

            if (    %args
                and defined( $args{pipeFile} )
                and defined( $args{options} )
                and ref( $args{options} ) eq 'ARRAY' )
            {

                if ( not defined( $args{opType} ) ) {
                    $args{opType} = 'button';
                }
                if ( not defined( $args{message} ) ) {
                    $args{message} = 'Please select';
                }
                $request->{interact} = {
                    title    => $args{title},      #交互操作标题
                    opType   => $args{opType},     #类型：button|input|select|mselect
                    message  => $args{message},    #交互操作文案
                    options  => $args{options},    #操作列表json数组，譬如：["commit","rollback"]
                    role     => $args{role},       #可以操作此操作的角色，如果空代表不控制
                    pipeFile => $args{pipeFile}    #交互管道文件
                };
            }
            else {
                $request->{interact} = undef;
            }

            $client->send( to_json($request) );
            $client->close();
            print("INFO: Inform node:$nodeId udpate status to waitInput success.\n");
        };
        if ($@) {
            print("WARN: Inform node:$nodeId udpate status to waitInput failed, $@\n");
        }
    }
    else {
        print("WARN: Inform node:$nodeId update status to waitInput failed:socket file $sockPath not exist.\n");
    }
    return;
}

sub getNodes {
    my $nodesJsonPath = $ENV{AUTOEXEC_NODES_PATH};

    my $nodesMap = {};
    my $fh       = IO::File->new("<$nodesJsonPath");
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            my $node = from_json($line);
            $nodesMap->{ $node->{nodeId} } = $node;
        }
        $fh->close();
    }

    return $nodesMap;
}

sub setErrFlag {
    my ($val) = @_;
    if ( not defined($val) ) {
        $ENV{runflag} = -1;
    }
    else {
        $ENV{runflag} = $val;
    }
}

sub exitWithFlag {
    my $flag = $ENV{runflag};
    exit($flag) if ( defined($flag) and $flag ne 0 );
}

sub getErrFlag {
    my $flag = $ENV{runflag};
    return int($flag) if ( defined($flag) );
    return 0 if ( not defined($flag) );
}

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

1;

