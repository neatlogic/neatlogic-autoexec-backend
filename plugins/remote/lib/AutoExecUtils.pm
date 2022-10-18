#!/usr/bin/perl

use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;

package AutoExecUtils;

use POSIX;
use IO::File;
use Encode;
use Encode::Guess;
use JSON qw(to_json from_json encode_json);

sub setEnv {
    umask(022);
    hidePwdInCmdLine();
    $ENV{OUTPUT_PATH} = "$FindBin::Bin/output.json";
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
            print("WARN: Open file $filePath failed $!\n");
        }
    }

    return $content;
}

sub getShellEncoding {
    my @uname  = uname();
    my $osType = $uname[0];

    my $encoding = 'UTF-8';

    if ( $osType =~ /Windows/i ) {
        eval(
            q{
                use Win32::API;
                if ( Win32::API->Import( 'kernel32', 'int GetACP()' ) ) {
                    $encoding = 'cp' . GetACP();
                }
            }
        );
    }
    else {
        my $lang = $ENV{LANG};
        if ( defined($lang) and $lang =~ /[^\.]+\.(.*)\s*$/ ) {
            $encoding = $1;
        }
        else {
            $encoding = 'utf-8';
        }
    }

    return $encoding;
}

sub convertTxtToUtf8 {
    my ($data) = @_;

    my $shellEncoding        = getShellEncoding();
    my $possibleEncodingsMap = {
        $shellEncoding => 1,
        'UTF-8'        => 1,
        'UTF-16LE'     => 1
    };
    my @possibleEncodings = keys(%$possibleEncodingsMap);

    my $decodeData = '';
    foreach my $line ( split( "\n", $data ) ) {
        my $decodedLine = $line;
        my $enc         = guess_encoding( $data, @possibleEncodings );
        if ( ref($enc) ) {
            if ( $enc->mime_name ne 'US-ASCII' ) {
                my $pEnc    = $enc->mime_name;
                my $destTmp = Encode::encode( 'UTF-8', Encode::decode( $pEnc,   $data ) );
                my $srcTmp  = Encode::encode( $pEnc,   Encode::decode( 'UTF-8', $destTmp ) );
                if ( $srcTmp eq $data ) {
                    $decodedLine = $destTmp;
                }
            }
        }
        else {
            if ( $enc eq 'utf-8-strict or utf8' ) {
                my $pEnc    = 'UTF-8';
                my $destTmp = Encode::encode( 'UTF-8', Encode::decode( $pEnc,   $data ) );
                my $srcTmp  = Encode::encode( $pEnc,   Encode::decode( 'UTF-8', $destTmp ) );
                if ( $srcTmp eq $data ) {
                    $decodedLine = $destTmp;
                }
            }
            elsif ( $enc !~ /ascii/i and $enc !~ /iso/i ) {
                foreach my $pEnc (@possibleEncodings) {
                    eval {
                        my $destTmp = Encode::encode( 'UTF-8', Encode::decode( $pEnc,   $data ) );
                        my $srcTmp  = Encode::encode( $pEnc,   Encode::decode( 'UTF-8', $destTmp ) );
                        if ( $srcTmp eq $data ) {
                            $decodedLine = $destTmp;
                            last;
                        }
                    };
                }
            }
        }
        $decodeData = $decodeData . $decodedLine;
    }

    return $decodeData;
}

sub saveOutput {
    my ( $outputData, $conv2Utf8 ) = @_;
    my $outputPath = "$FindBin::Bin/output.json";

    if ( defined($outputPath) and $outputPath ne '' ) {
        my $fh = IO::File->new(">$outputPath");
        if ( defined($fh) ) {
            my $jsonTxt = to_json( $outputData, { utf8 => 0, pretty => 1 } );
            if ( $conv2Utf8 == 1 ) {
                $jsonTxt = convertTxtToUtf8($jsonTxt);
            }
            print $fh ($jsonTxt);
            $fh->close();
        }
        else {
            die("ERROR: Can not open output file:$outputPath to write.\n");
        }
    }
}

1;

