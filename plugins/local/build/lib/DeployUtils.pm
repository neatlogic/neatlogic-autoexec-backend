#!/usr/bin/perl
use strict;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/lib";

package DeployUtils;
use Cwd;
use ServerAdapter;

sub deployInit {
    my ( $namePath, $version ) = @_;

    my $dpPath     = $ENV{_DEPLOY_PATH};
    my $dpIdPath   = $ENV{_DEPLOY_ID_PATH};
    my $deployConf = $ENV{_DEPLOY_CONF};

    my $deployEnv = {};
    if ( defined($deployConf) and $deployConf ne '' ) {
        $deployEnv = from_json($deployConf);
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
        $ENV{ $level . "_NAME" }         = $dpIds[$idx];
        $deployEnv->{ $level . "_ID" }   = $dpIds[$idx];
        $deployEnv->{ $level . "_NAME" } = $dpIds[$idx];
        $idx                             = $idx + 1;
    }

    my $autoexecHome = $ENV{AUTOEXEC_HOME};
    if ( not defined($autoexecHome) or $autoexecHome eq '' ) {
        $autoexecHome               = Cwd::realpath("$FindBin::Bin/../../..");
        $ENV{AUTOEXEC_HOME}         = $autoexecHome;
        $deployEnv->{AUTOEXEC_HOME} = $autoexecHome;
    }
    my $dataPath = "$autoexecHome/data/verdata/$ENV{SYS_ID}/$ENV{MODULE_ID}";
    $ENV{_DEPLOY_DATA_PATH} = $dataPath;
    my $prjPath = "$dataPath/workspace/project";
    $ENV{_DEPLOY_PRJ_PATH} = $prjPath;

    if ( defined($version) and $version ne '' ) {
        $ENV{VERSION} = $version;
        $deployEnv->{VERSION} = $version;
    }
    else {
        $deployEnv->{VERSION} = $ENV{VERSION};
    }

    $deployEnv->{ID_PATH}   = $dpIdPath;
    $deployEnv->{NAME_PATH} = $dpPath;
    $deployEnv->{DATA_PATH} = $dataPath;
    $deployEnv->{PRJ_PATH}  = $prjPath;

    return $deployEnv;
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

1;
