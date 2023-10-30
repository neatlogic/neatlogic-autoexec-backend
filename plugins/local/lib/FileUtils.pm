#!/usr/bin/perl
package FileUtils;
use strict;
use FindBin;
use IO::File;
use File::Copy;
use File::Find;
use Digest::MD5;
use File::Basename;

our $md5ListFileName = "md5checksum.list.txt";

sub getFileContent {
    my ($filePath) = @_;
    my $content;

    if ( -f $filePath ) {
        my $fh = new IO::File("<$filePath");

        if ( defined($fh) ) {
            sysread( $fh, $content, 256 );
            chomp($content);
            $fh->close();
        }
        else {
            die("ERROR: Read file:$filePath failed, $!.\n");
        }
    }

    return $content;
}

sub getFileMd5 {
    my ($filePath) = @_;
    my $fileFH = new IO::File("<$filePath");

    my $md5Hash = '';
    if ( defined($fileFH) ) {
        $md5Hash = Digest::MD5->new->addfile(*$fileFH)->hexdigest();
        $fileFH->close();
    }
    else {
        die("ERROR: Read md5 file:$filePath failed, $!\n");
    }

    return $md5Hash;
}

sub appendFileMd5 {
    my ( $file, $filePath, $md5ListFH ) = @_;

    my $md5Sum = getFileMd5($file);
    if ( not print $md5ListFH ( $md5Sum, "  ", $filePath, "\n" ) ) {
        die("ERROR: Write $filePath md5 to file failed, $!\n");
    }
}

sub checkFileMd5 {
    my ($file) = @_;

    if ( -f $file ) {
        my $md5Provided = getFileContent("$file.md5");
        my $md5Sum      = getFileMd5($file);

        if ( $md5Provided ne $md5Sum ) {
            die("ERROR: $file md5 check failed, actual md5checksum($md5Sum) not equal to($md5Provided).\n");
        }
    }
    else {
        die("ERROR: Check file md5 failed, $file not a file.\n");
    }
}

sub genMd5 {
    my ($dest) = @_;

    my $hasError = 0;

    my $destLen = length($dest);

    my $md5ListFH;

    my $md5SumListPath;

    if ( -f $dest ) {
        my $destDir  = dirname($dest);
        my $filePath = basename($dest);

        $md5SumListPath = "$destDir/$md5ListFileName";
        $md5ListFH      = IO::File->new(">$md5SumListPath");

        eval { appendFileMd5( $dest, $filePath, $md5ListFH ); };
        if ($@) {
            $hasError = 1;
            my $errMsg = $@;
            $errMsg =~ s/ at\s*.*$//;
            print($errMsg );
        }
    }
    elsif ( -d $dest ) {
        $md5SumListPath = "$dest/$md5ListFileName";
        $md5ListFH      = IO::File->new(">$md5SumListPath");

        find(
            {
                wanted => sub {
                    my $file = $_;
                    if ( $file eq '.svn' or $file eq '.git' or $file eq "$md5ListFileName" ) {
                        $File::Find::prune = 1;
                        return;
                    }

                    my $fullDir = $File::Find::name;
                    if ( -f $file and $fullDir ne $md5SumListPath ) {
                        eval { appendFileMd5( $file, substr( $fullDir, $destLen + 1 ), $md5ListFH ); };
                        if ($@) {
                            $hasError = 1;
                            my $errMsg = $@;
                            $errMsg =~ s/ at\s*.*$//;
                            print($errMsg );
                        }
                    }
                },
                follow => 0
            },
            $dest
        );
    }

    if ( $hasError == 1 ) {
        die("ERROR: Generate md5 for $dest failed.\n");
    }
}

sub checkMd5 {
    my ($dest) = @_;

    my $hasError = 0;

    my $destDir = $dest;

    if ( -f $dest ) {
        $destDir = dirname($dest);
    }

    my $md5ListPath = "$destDir/$md5ListFileName";

    if ( not -f $md5ListPath ) {
        return;
    }

    my $fh = IO::File->new("<$md5ListPath");

    if ( defined($fh) ) {
        my $line;
        my $md5Sum;
        my $md5Provided;
        my $filePath;

        while ( $line = $fh->getline() ) {
            chomp($line);
            ( $md5Provided, $filePath ) = split( '  ', $line );
            eval { $md5Sum = getFileMd5("$destDir/$filePath"); };
            if ($@) {
                $hasError = 1;
                my $errMsg = $@;
                $errMsg =~ s/ at\s*.*$//;
                print($errMsg );
            }

            if ( $md5Provided ne $md5Sum ) {
                $hasError = 1;
                print("ERROR: $filePath md5 check failed, actual md5checksum($md5Sum) not equal to($md5Provided).\n");
            }
        }
    }
    else {
    }

    if ( $hasError == 1 ) {
        die("ERROR: Check md5 for $dest failed.\n");
    }
    else {
        print("INFO: Check md5 for $dest success.\n");
    }
}

1;

