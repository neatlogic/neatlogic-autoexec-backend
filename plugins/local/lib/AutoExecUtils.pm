#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use POSIX;
use IO::Socket;
use IO::Socket::SSL;
use IO::Socket::UNIX;
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

sub informNodeWaitInput {
    my ($nodeId) = @_;
    my $sockPath = $ENV{AUTOEXEC_WORK_PATH} . '.job.sock';

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

