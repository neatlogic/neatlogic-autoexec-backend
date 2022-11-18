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

sub randString($) {
    my ($len) = @_;

    my @elements =
        ( '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'm', 'n', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z' );
    my $elementsCount = scalar(@elements);

    my $str = '';
    my $i;
    for ( $i = 3 ; $i <= $len ; $i++ ) {
        $str = $str . $elements[ int( rand( $len - 1 ) ) ];
    }

    return $str;
}

sub getShellEncoding {
    my @uname  = uname();
    my $osType = $uname[0];

    my $encoding = 'GBK';

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
        my $enc         = guess_encoding( $line, @possibleEncodings );
        if ( ref($enc) ) {
            my $pEnc = $enc->name;
            if ( $pEnc ne 'ascii' ) {
                my $destTmp = Encode::encode( 'UTF-8', Encode::decode( $pEnc,   $line ) );
                my $srcTmp  = Encode::encode( $pEnc,   Encode::decode( 'UTF-8', $destTmp ) );
                if ( $srcTmp eq $line ) {
                    $decodedLine = $destTmp;
                }
            }
        }
        else {
            if ( $enc eq 'utf-8-strict or utf8' ) {
                my $pEnc    = 'UTF-8';
                my $destTmp = Encode::encode( 'UTF-8', Encode::decode( $pEnc,   $line ) );
                my $srcTmp  = Encode::encode( $pEnc,   Encode::decode( 'UTF-8', $destTmp ) );
                if ( $srcTmp eq $line ) {
                    $decodedLine = $destTmp;
                }
            }
            elsif ( $enc !~ /ascii/i and $enc !~ /iso/i ) {
                foreach my $pEnc (@possibleEncodings) {
                    eval {
                        my $destTmp = Encode::encode( 'UTF-8', Encode::decode( $pEnc,   $line ) );
                        my $srcTmp  = Encode::encode( $pEnc,   Encode::decode( 'UTF-8', $destTmp ) );
                        if ( $srcTmp eq $line ) {
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

sub evalDsl {
    my ( $data, $checkDsl ) = @_;
    $checkDsl =~ s/\[\s*([^\}]+)\s*\]/\$data->\{'$1'\}/g;

    my $ret = eval($checkDsl);

    return $ret;
}

sub JsonToTableCheck {
    my ( $obj, $fieldNames, $filter, $checkDsl ) = @_;

    my $errorCode = 0;

    my $tblHeader = {};
    my $tblRows;

    if ( ref($obj) eq 'HASH' ) {
        $tblRows = hashToTable( $obj, undef, $tblHeader );
    }
    elsif ( ref($obj) eq 'ARRAY' ) {
        foreach my $subObj (@$obj) {
            my $myRows = hashToTable( $subObj, undef, $tblHeader );
            push( @$tblRows, @$myRows );
        }
    }

    if ( not defined($fieldNames) ) {
        @$fieldNames = sort ( keys(%$tblHeader) );
    }

    foreach my $fieldName (@$fieldNames) {
        print( $fieldName, "\t" );
    }
    print("\n");

    my $matched = 0;
    foreach my $row (@$tblRows) {
        if ( defined($filter) ) {
            my $filterRet = evalDsl( $row, $filter );
            if ( not $filterRet ) {
                next;
            }
        }

        $matched = 1;
        if ( defined($checkDsl) ) {
            my $ret = evalDsl( $row, $checkDsl );
            if ($ret) {
                print("FINE: ");
            }
            else {
                $errorCode = 1;
                print("ERROR: ");
            }
        }

        foreach my $fieldName (@$fieldNames) {
            print( $row->{$fieldName}, "\t" );
        }
        print("\n");
    }

    if ( $matched == 0 ) {
        if ( defined($filter) ) {
            print("ERROR: No data matched filter:$filter\n");
        }
        else {
            print("ERROR: No data return from api.\n");
        }
        $errorCode = 2;
    }

    return $errorCode;
}

sub hashToTable {
    my ( $obj, $parentPath, $tblHeader ) = @_;

    #获取所有的简单属性，构造第一行
    my $myRow = {};
    while ( my ( $key, $val ) = each(%$obj) ) {
        my $thisPath;
        if ( defined($parentPath) ) {
            $thisPath = "$parentPath.$key";
        }
        else {
            $thisPath = "$key";
        }

        if ( ref($val) eq '' ) {
            $tblHeader->{$thisPath} = 1;
            $myRow->{$thisPath}     = $val;
        }
    }

    my $myRows = [$myRow];

    while ( my ( $key, $val ) = each(%$obj) ) {
        if ( ref($val) eq '' ) {
            next;
        }

        my $thisPath;
        if ( defined($parentPath) ) {
            $thisPath = "$parentPath.$key";
        }
        else {
            $thisPath = "$key";
        }

        if ( ref($val) eq 'ARRAY' ) {
            if ( scalar(@$val) > 0 ) {
                my $newRows = [];
                foreach my $subObj (@$val) {
                    my $myChildRows = hashToTable( $subObj, $thisPath, $tblHeader );
                    foreach my $childRow (@$myChildRows) {
                        foreach my $curRow (@$myRows) {
                            while ( my ( $curKey, $curVal ) = each(%$curRow) ) {
                                $childRow->{$curKey} = $curVal;
                            }
                            push( @$newRows, $childRow );
                        }
                    }
                }
                if ( scalar(@$newRows) > 0 ) {
                    $myRows = $newRows;
                }
            }
        }
        elsif ( ref($val) eq 'HASH' ) {
            my $myChildRows = hashToTable( $val, $thisPath, $tblHeader );

            if ( scalar(@$myChildRows) > 0 ) {
                my $newRows = [];
                foreach my $childRow (@$myChildRows) {
                    my %tmpRow = %$childRow;
                    foreach my $curRow (@$myRows) {
                        while ( my ( $curKey, $curVal ) = each(%$curRow) ) {
                            $childRow->{$curKey} = $curVal;
                        }
                        push( @$newRows, $childRow );
                    }
                }
                $myRows = $newRows;
            }
        }
    }

    return $myRows;
}

1;

