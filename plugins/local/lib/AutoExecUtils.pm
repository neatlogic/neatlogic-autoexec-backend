#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

package AutoExecUtils;

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
use File::Basename;
use Cwd;
use File::Glob qw(bsd_glob);
use JSON qw(from_json to_json);

my $READ_TMOUT = 86400;
my $TERM_CHARSET;

sub setEnv {

    #hide password in command line
    hidePwdInCmdLine();
}

sub hidePwdInCmdLine {
    my @args = ($0);
    my $arg;
    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        $arg = $ARGV[$i];
        if ( $arg =~ /[-]+\w*pass\w*[^=]/ or $arg =~ /[-]+\w*account\w*[^=]/ ) {
            push( @args, $arg );
            push( @args, '******' );
            $i = $i + 1;
        }
        else {
            $arg =~ s/"password":\K".*?"/"******"/ig;
            push( @args, $arg );
        }
    }
    $0 = join( ' ', @args );
}

sub saveOutput {
    my ($outputData) = @_;
    my $outputPath = $ENV{OUTPUT_PATH};

    print("INFO: Try to save output to $outputPath.\n");
    if ( defined($outputPath) and $outputPath ne '' ) {
        my $fh = IO::File->new(">$outputPath");
        if ( defined($fh) ) {
            print $fh ( to_json( $outputData, { utf8 => 0 } ) );
            $fh->close();
        }
        else {
            die("ERROR: Can not open output file:$outputPath to write.\n");
        }
    }
    else {
        print("WARN: Could not save output file, because of environ OUTPUT_PATH not defined.\n");
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
            print("[wait interact]$message\n");
            STDOUT->flush();

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
                Peer    => $sockPath,
                Type    => IO::Socket::SOCK_DGRAM,
                Timeout => 10
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
            print("INFO: Inform runner udpate status to waitInput success.\n");
        };
        if ($@) {
            print("WARN: Inform runner udpate status to waitInput failed, $@\n");
        }
    }
    else {
        print("WARN: Inform runner update status to waitInput failed:socket file $sockPath not exist.\n");
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

1;

