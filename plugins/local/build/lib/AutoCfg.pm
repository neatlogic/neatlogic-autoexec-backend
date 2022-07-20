#!/usr/bin/perl
use strict;

package AutoCfg;
use FindBin;
use IO::String;
use File::Temp;
use File::Path;
use File::Basename;
use IO::File;
use File::Find;
use File::Copy;
use File::Glob qw(bsd_glob);
use Cwd;
use Encode;
use Data::Dumper;

use DeployUtils;
use FileUtils;

my $TMPDIR = Cwd::abs_path("$FindBin::Bin/../../../tmp");
my $suffix = 'autocfg';

sub new {
    my ( $pkg, %args ) = @_;

    my $self = \%args;
    bless( $self, $pkg );

    $self->{hasError} = 0;

    #$buildEnv, $orgCfgFiles, $version, $charset, $followZip, $cleanAutoCfgFiles, $followTar, $checkOrg, $pureDir, $md5Check
    my $buildEnv = $args{buildEnv};
    my $charset  = $args{charset};

    $self->{buildEnv}          = $buildEnv;
    $self->{orgCfgFiles}       = $args{orgCfgFiles};
    $self->{version}           = $args{version};
    $self->{charset}           = $charset;
    $self->{followZip}         = $args{followZip};
    $self->{followTar}         = $args{followTar};
    $self->{cleanAutoCfgFiles} = $args{doClean};
    $self->{checkOrg}          = $args{checkOrg};
    $self->{pureDir}           = $args{pureDir};
    $self->{md5Check}          = $args{md5Check};

    if ( not defined( $self->{followZip} ) ) {
        $self->{followZip} = 1;
    }

    $self->{envName} = $buildEnv->{ENV_NAME};

    my $dirInfo   = DeployUtils->getDataDirStruct($buildEnv);
    my $mirrorDir = $dirInfo->{mirror};
    my $distDir   = $dirInfo->{distribute};
    my $distSrc   = "$distDir/app";
    my $mirrorSrc = "$mirrorDir/app";
    my $dbSrc     = "$distDir/db";

    my @autoCfgDocRoots = ();
    if ( -d $distSrc and defined( scalar( bsd_glob("$distSrc/*") ) ) ) {
        push( @autoCfgDocRoots, $distSrc );
    }

    if ( -d $mirrorSrc and defined( scalar( bsd_glob("$mirrorSrc/*") ) ) ) {
        push( @autoCfgDocRoots, $mirrorSrc );
    }

    if ( -d $dbSrc and defined( scalar( bsd_glob("$dbSrc/*") ) ) ) {
        push( @autoCfgDocRoots, $dbSrc );
    }

    $self->{autoCfgDocRoots} = \@autoCfgDocRoots;
    $self->{dbSrc}           = $dbSrc;
    $self->{distSrc}         = $distSrc;
    $self->{mirrorSrc}       = $mirrorSrc;

    my $packCfgMap = $args{autoCfg};
    $self->convertCfgMapCharset( $packCfgMap, $charset );
    my $insCfgList = $args{insCfgList};
    $self->convertInsCfgListCharset( $insCfgList, $charset );

    $self->{packCfgMap} = $packCfgMap;
    $self->{insCfgMaps} = $args{insCfgMaps};

    my $insCount = scalar(@$insCfgList);
    $self->{insCount}   = $insCount;
    $self->{insCfgList} = $insCfgList;

    return $self;
}

sub toDirsMap {
    my ( $self, $dirs ) = @_;

    my $root = {};

    foreach my $dir (@$dirs) {
        my $cur = $root;
        my $pwd = '';

        my @subDirs = split( '/', $dir );
        if ( $dir =~ /\/$/ ) {
            my $lastIdx = scalar(@subDirs) - 1;
            $subDirs[$lastIdx] = $subDirs[$lastIdx] . '/';
        }

        my $subDir;
        foreach $subDir (@subDirs) {
            if ( not exists( $cur->{$subDir} ) ) {
                $cur->{$subDir} = {};
            }

            $cur->{'..'} = $cur;
            $cur = $cur->{$subDir};

            if ( $pwd eq '' ) {
                $pwd = $subDir;
            }
            else {
                $pwd = "$pwd/$subDir";
            }

            $cur->{'...'} = $pwd;
        }
    }

    return $root;
}

sub mergeMd5SumList {
    my ( $self, $fullMd5List, $updateMd5List ) = @_;

    my $updateFh  = IO::File->new("<$updateMd5List");
    my $updateMap = {};

    if ( not defined($updateFh) ) {
        die("ERROR: open file $updateMd5List failed, $!\n");
    }
    my $line;
    my $md5Sum;
    my $filePath;
    while ( $line = $updateFh->getline() ) {
        chomp($line);
        ( $md5Sum, $filePath ) = split( '  ', $line );
        $updateMap->{$filePath} = $md5Sum;
    }
    close($updateFh);

    my $newFh = IO::File->new(">$updateMd5List");
    if ( not defined($newFh) ) {
        die("ERROR: create file $updateMd5List failed, $!\n");
    }

    my $fullFh = IO::File->new("<$fullMd5List");
    if ( not defined($fullFh) ) {
        die("ERROR: open file $fullMd5List failed, $!\n");
    }
    my $line;
    my $md5Sum;
    my $filePath;
    while ( $line = $fullFh->getline() ) {
        chomp($line);
        ( $md5Sum, $filePath ) = split( '  ', $line );
        if ( defined( $updateMap->{$filePath} ) ) {
            $md5Sum = $updateMap->{$filePath};
        }

        print $newFh ( $md5Sum, '  ', $filePath, "\n" );
    }
    close($updateFh);
    close($newFh);
}

sub refreshFilesMd5 {
    my ( $self, $autoCfgDocRoot, $dirs ) = @_;

    my $hasMd5    = 0;
    my $processed = {};

    foreach my $dir (@$dirs) {

        my $possibleDir = $dir;

        my @possibleDirs = ();
        $possibleDir =~ s/\.autocfg$//;
        push( @possibleDirs, $possibleDir );

        $possibleDir =~ s/\.[^\.]+$//;
        push( @possibleDirs, $possibleDir );

        $possibleDir =~ s/\.[^\.]+$//;
        push( @possibleDirs, $possibleDir );

        my $hasRefresh = 0;
        foreach $possibleDir (@possibleDirs) {
            my $fullDir = "$autoCfgDocRoot/$possibleDir";
            if ( -f $fullDir ) {
                if ( not defined( $processed->{$possibleDir} ) ) {
                    $hasMd5 = 1;
                    print("INFO: refresh file:$possibleDir md5.\n");
                    my $md5Sum = FileUtils::getFileMd5($fullDir);
                    $processed->{$possibleDir} = $md5Sum;
                    $hasRefresh = 1;
                }
            }
        }

        if ( $hasRefresh == 1 ) {
            next;
        }

        my $prefixDir = $autoCfgDocRoot;
        my $prefixLen = length($prefixDir);
        my @subDirs   = split( '/', $dir );
        foreach my $subDir (@subDirs) {
            $prefixDir = "$prefixDir/$subDir";
            if ( -f $prefixDir ) {
                my $filePath = substr( $prefixDir, $prefixLen + 1 );
                if ( not defined( $processed->{$filePath} ) ) {
                    $hasMd5 = 1;
                    print("INFO: refresh file:$filePath md5.\n");
                    my $md5Sum = FileUtils::getFileMd5($prefixDir);
                    $processed->{$prefixDir} = $md5Sum;
                }
            }
        }
    }

    return $hasMd5;
}

sub sortByLen {
    my $left  = $a;
    my $right = $b;

    my $ret = length($left) <=> length($right);

    return $ret;
}

sub getAllSubFiles {
    my ( $self, $root, $dir, $pkgFiles ) = @_;

    my $beginIdx = length($dir);

    if ( $dir !~ /\/$/ and defined($dir) and $dir ne '' ) {
        $beginIdx = $beginIdx + 1;
    }

    my $cur = $root;
    foreach my $subDir ( split( '/', $dir ) ) {
        $cur = $cur->{$subDir};
    }

    my @subDirs = ();

    my @dirs = ($cur);
    my %seen;
    while ( my $pwd = shift @dirs ) {
        my @files = keys(%$pwd);
        foreach my $file (@files) {
            if ( $file eq '...' or $file eq '..' ) {
                next;
            }
            my $dir  = $pwd->{$file};
            my $path = $dir->{'...'};
            if ( scalar( keys(%$dir) ) > 2 and ( not defined($pkgFiles) or $pkgFiles->{$path} ne 1 ) ) {
                if ( $seen{$path} ) {
                    next;
                }

                $seen{$path} = 1;
                push( @dirs, $dir );
            }
            else {
                push( @subDirs, substr( $path, $beginIdx ) );
            }
        }
    }

    my @temp = sort sortByLen (@subDirs);
    return \@temp;
}

sub parsePreDefinedCfgFiles {
    my ( $self, $autoCfgDocRoot, $cfgFiles, $pkgFiles, $rplOrgFiles ) = @_;
    my $env = $self->{envName};

    my @newCfgFiles = ();

    foreach my $cfgFile (@$cfgFiles) {
        my $isDir = 0;
        if ( $cfgFile =~ /\/$/ ) {
            $isDir = 1;
        }

        my @subDirs = split( '/', $cfgFile );
        my $dir     = $subDirs[0];

        my $fileExists = 1;
        my $seenPkg    = 0;

        my $i = 0;
        for ( $i = 1 ; $i < scalar(@subDirs) ; $i++ ) {
            my $zipType = $self->getZipType($dir);
            if ( $zipType ne 'plain' ) {
                $pkgFiles->{$dir} = 1;

                if ( $seenPkg == 0 ) {
                    $seenPkg = 1;

                    if ( -e "$autoCfgDocRoot/$dir" ) {
                        $fileExists = 1;
                    }
                    else {
                        $fileExists = 0;
                    }
                }
            }
            elsif ( $seenPkg == 0 ) {
                if ( -e "$autoCfgDocRoot/$dir" ) {
                    $fileExists = 1;
                }
                else {
                    $fileExists = 0;
                }
            }

            $dir = $dir . '/' . $subDirs[$i];
        }

        if ( $fileExists == 0 ) {
            print("ERROR: $suffix config file:$cfgFile not exists.\n");
            $self->{hasError} = $self->{hasError} + 1;
        }

        my $orgFile = $cfgFile;
        if ( $orgFile =~ s/(\.$env\.[^\/]*?)\.$suffix\/.*$/\//i ) {
            $rplOrgFiles->{$orgFile} = 1;
            $rplOrgFiles->{"$orgFile$1"} = 2;
        }
        elsif ( $orgFile =~ s/(\.$env\.[^\/]*?)\.$suffix$//i ) {
            $rplOrgFiles->{$orgFile} = 1;
            $rplOrgFiles->{"$orgFile$1"} = 2;
        }
        elsif ( $orgFile =~ s/(\.$env)\.$suffix\/.*$/\//i ) {
            $rplOrgFiles->{$orgFile} = 1;
            $rplOrgFiles->{"$orgFile$1"} = 2;
        }
        elsif ( $orgFile =~ s/(\.$env)\.$suffix$//i ) {
            $rplOrgFiles->{$orgFile} = 1;
            $rplOrgFiles->{"$orgFile$1"} = 2;
        }

        if ( $cfgFile !~ /\.$suffix$/ ) {
            print("ERROR: $suffix config file:$cfgFile is not ended with extention \".$suffix\"\n");
            $self->{hasError} = $self->{hasError} + 1;
        }
        elsif ( $fileExists == 1 ) {
            push( @newCfgFiles, $cfgFile );
        }
    }

    return \@newCfgFiles;
}

sub replacePlaceHolder {
    my ( $self, $autoCfgDocRoot, $fileName, $cfgName, $rplOrgFiles, $insInfo ) = @_;
    my $env               = $self->{envName};
    my $packCfgMap        = $self->{packCfgMap};
    my $cleanAutoCfgFiles = $self->{cleanAutoCfgFiles};
    my $checkOrg          = $self->{checkOrg};

    my $insCfgMaps = $self->{insCfgMaps};
    my $insCfgMap  = {};
    if ( defined($insInfo) ) {
        $insCfgMap = $insCfgMaps->{ $insInfo->{uniqName} };
    }

    my $count           = 0;
    my $insCount        = 0;
    my $orgFileName     = $fileName;
    my $orgCfgName      = $cfgName;
    my $recfgAgain      = 0;
    my $recfgAgainAdded = 0;

    $fileName    =~ s/\/$//;
    $orgFileName =~ s/\.$suffix(\/|$)//;
    $orgCfgName  =~ s/\.$suffix(\/|$)//;

    my $orgFileDir = dirname($orgFileName);
    mkpath($orgFileDir) if ( not -e $orgFileDir );

    $env = lc($env);

    #$instance = lc($instance);
    if ( defined($insInfo) and $fileName =~ /\.$env\.(.+)\.$suffix(\/|$)/i ) {
        my $expectIns = lc($1);

        my $insUniqName = $insInfo->{uniqName};
        my $insName     = $insInfo->{nodeName};
        my $insHost     = $insInfo->{host};

        my $canAutocfg = 0;

        if ( $expectIns eq $insHost ) {
            if ( $insInfo->{hostConflictCount} > 0 ) {
                $self->{hasError} = $self->{hasError} + 1;
                print("ERROR: Instance ip($insHost) not unique, can not auto config $fileName.\n");
            }
            else {
                $canAutocfg = 1;
            }
        }
        elsif ( $expectIns eq $insName ) {
            if ( $insInfo->{nameConflictCount} > 0 ) {
                $self->{hasError} = $self->{hasError} + 1;
                print("ERROR: Instance name($insName) not unique, can not auto config $fileName.\n");
            }
            else {
                $canAutocfg = 1;
            }
        }
        elsif ( $expectIns eq $insUniqName ) {
            $canAutocfg = 1;
        }
        elsif ( not defined( $insCfgMaps->{ lc($expectIns) } ) ) {
            $self->{hasError} = $self->{hasError} + 1;
            print("ERROR: Instance identifier($expectIns) that substract from $fileName not exists.\n");
        }

        if ( $canAutocfg == 1 ) {
            $rplOrgFiles->{$orgFileName} = 2;
            $orgFileName =~ s/\.$env\.$expectIns//i;
            $orgCfgName  =~ s/\.$env\.$expectIns//i;

            if ( $checkOrg == 1 and not( -e $orgFileName or -e "$autoCfgDocRoot/$orgCfgName" ) ) {
                print("ERROR: Original file:$orgCfgName for $cfgName not found.");
                $self->{hasError} = $self->{hasError} + 1;
            }

            if ( -f $fileName ) {
                $rplOrgFiles->{$orgFileName} = 1;

                if ( not -f "$orgFileName.$suffix" ) {
                    $recfgAgainAdded = 1;
                }

                if ( not copy( $fileName, "$orgFileName.$suffix" ) ) {
                    $self->{hasError} = $self->{hasError} + 1;
                    print("ERROR: copy $fileName to $orgFileName.$suffix failed:$!\n");
                }
                chmod( ( stat($fileName) )[2], "$orgFileName.$suffix" );
                if ( $cleanAutoCfgFiles == 1 ) {
                    rmtree($fileName);
                    rmtree("$fileName.md5");
                }
                $fileName   = "$orgFileName.$suffix";
                $recfgAgain = 1;
            }
            elsif ( -d $fileName ) {

                #rmtree($orgFileName);
                DeployUtils->copyTree( $fileName, $orgFileName );
            }
            elsif ( not -e $fileName ) {
                print("ERROR: $cfgName not found.\n");
                $self->{hasError} = $self->{hasError} + 1;
            }

            $insCount++;
        }
    }
    elsif ( $fileName =~ /\.$env\.$suffix(\/|$)/i ) {
        $rplOrgFiles->{$orgFileName} = 2;
        $orgFileName =~ s/\.$env//i;
        $orgCfgName  =~ s/\.$env//i;

        if ( $checkOrg == 1 and not( -e $orgFileName or -e "$autoCfgDocRoot/$orgCfgName" ) ) {
            print("ERROR: original file:$orgCfgName for $cfgName not found.\n");
            $self->{hasError} = $self->{hasError} + 1;
        }

        if ( -f $fileName ) {
            $rplOrgFiles->{$orgFileName} = 1;

            if ( not -f "$orgFileName.$suffix" ) {
                $recfgAgainAdded = 1;
            }

            if ( not copy( $fileName, "$orgFileName.$suffix" ) ) {
                $self->{hasError} = $self->{hasError} + 1;
                print("ERROR: copy $fileName to $orgFileName.$suffix failed:$!\n");
            }
            chmod( ( stat($fileName) )[2], "$orgFileName.$suffix" );
            if ( $cleanAutoCfgFiles == 1 ) {
                rmtree($fileName);
                rmtree("$fileName.md5");
            }
            $fileName   = "$orgFileName.$suffix";
            $recfgAgain = 1;
        }
        elsif ( -d $fileName ) {

            #rmtree($orgFileName);
            DeployUtils->copyTree( $fileName, $orgFileName );
        }
        elsif ( not -e $fileName ) {
            print("ERROR: $cfgName not found.\n");
            $self->{hasError} = $self->{hasError} + 1;
        }

        $count++;
    }

    if ( $fileName !~ /\.$env\./i and ( scalar(%$insCfgMap) > 0 or scalar(%$packCfgMap) > 0 ) ) {
        my $content;
        $orgCfgName =~ s/\.$suffix$//i;
        my $orgFileName1 = $orgFileName;
        $orgFileName1 =~ s/\.[^\.]+$/\.$env/;
        my $orgFileName2 = $orgFileName;
        $orgFileName2 =~ s/\.[^\.]+\.([^\.]+)$/\.$env\.$1/;

        my $orgFileName3 = $orgFileName;
        $orgFileName3 =~ s/\.[^\.]+$//;
        my $orgFileName4 = $orgFileName;
        $orgFileName4 =~ s/\.[^\.]+\.[^\.]+$//;

        my $orgCfgName3 = $orgCfgName;
        $orgCfgName3 =~ s/\.[^\.]+$//;
        my $orgCfgName4 = $orgCfgName;
        $orgCfgName4 =~ s/\.[^\.]+\.[^\.]+$//;

        if ( not -e $fileName ) {
            print("ERROR: $cfgName not found.\n");
            $self->{hasError} = $self->{hasError} + 1;
        }

        if ( $checkOrg == 1
            and not( -f $orgFileName or -f "$autoCfgDocRoot/$orgCfgName" or -f $orgFileName3 or -f "$autoCfgDocRoot/$orgCfgName3" or -f $orgFileName4 or -f "$autoCfgDocRoot/$orgCfgName4" ) )
        {
            $orgCfgName =~ s/\.$suffix$//i;
            print("ERROR: original file:$orgCfgName for $cfgName not found.\n");
            $self->{hasError} = $self->{hasError} + 1;
        }

        if (
            -f $fileName
            and (
                ( $rplOrgFiles->{$orgFileName} == 1 or -f $orgFileName or -f "$autoCfgDocRoot/$orgCfgName" )
                or (    $checkOrg == 0
                    and $rplOrgFiles->{$orgFileName1} != 2
                    and $rplOrgFiles->{$orgFileName2} != 2
                    and not( -f $orgFileName3 or -f "$autoCfgDocRoot/$orgCfgName3" or -f $orgFileName4 or -f "$autoCfgDocRoot/$orgCfgName4" ) )
            )
            )
        {

            my $sfh = IO::File->new("<$fileName");

            if ( defined($sfh) ) {
                my $line;
                while ( $line = <$sfh> ) {
                    my $key;
                    my $notPlaceholders = {};
                    foreach $key ( keys(%$insCfgMap) ) {
                        if ( $line =~ s/\{\{\s*$key\s*\}\}/$insCfgMap->{$key}/g ) {
                            $insCount++;
                            if ( $insCfgMap->{$key} =~ /(\{\{.+?\}\})/ ) {
                                $notPlaceholders->{$1} = 1;
                            }
                        }
                    }

                    foreach $key ( keys(%$packCfgMap) ) {
                        if ( not exists( $insCfgMap->{$key} ) ) {
                            if ( $line =~ s/\{\{\s*$key\s*\}\}/$packCfgMap->{$key}/g ) {
                                $count++;
                                if ( $packCfgMap->{$key} =~ /(\{\{.+?\}\})/ ) {
                                    $notPlaceholders->{$1} = 1;
                                }
                            }
                        }
                    }

                    $content = $content . $line;

                    if ( $line =~ /\{\{(.+?)\}\}/ ) {
                        my $key = $1;
                        if ( not defined( $notPlaceholders->{$key} ) ) {
                            if ( $key =~ /^[\w\-\.]+$/ ) {
                                print("ERROR:config place holder:$key value not found.\n");
                                $self->{hasError} = $self->{hasError} + 1;
                            }
                            else {
                                print("WARN:malform place holder:$key value not found(the key has special characters).\n");
                            }
                        }
                    }
                }

                $sfh->close();

                if ( $insCount > 0 or $count > 0 or $recfgAgain == 1 ) {
                    my $dfh = IO::File->new(">$orgFileName");
                    if ( defined($dfh) ) {
                        print $dfh ($content);
                        $dfh->close();
                        chmod( ( stat($fileName) )[2], $orgFileName );
                    }
                    else {
                        $self->{hasError} = $self->{hasError} + 1;
                        print("ERROR:can not rewrite file $orgFileName while modify config file.\n");
                    }

                    if ( $recfgAgain == 1 and $recfgAgainAdded == 1 ) {
                        rmtree($fileName);
                    }
                }
            }
            else {
                $self->{hasError} = $self->{hasError} + 1;
                print("ERROR:can not read file $orgFileName while modify config file.\n");
            }
        }
    }
    elsif ( $recfgAgain == 1 and -f $fileName ) {
        if ( $checkOrg == 1 and $rplOrgFiles->{$orgFileName} == 1 and not( -f $orgFileName or -f "$autoCfgDocRoot/$orgCfgName" ) ) {
            $orgCfgName =~ s/\.$suffix$//i;
            print("ERROR: original file:$orgCfgName for $cfgName not found.\n");
            $self->{hasError} = $self->{hasError} + 1;
        }

        if ( not copy( $fileName, $orgFileName ) ) {
            $self->{hasError} = $self->{hasError} + 1;
            print("ERROR: copy file $fileName to $orgFileName failed:$!\n");
        }

        if ( $recfgAgain == 1 and $recfgAgainAdded == 1 ) {
            rmtree($fileName);
        }
    }

    if ( $cleanAutoCfgFiles == 1 and -e $fileName ) {
        rmtree($fileName);
        rmtree("$fileName.md5");
    }

    #print("DEBUG:instance has replace, count:$insCount\n") if ( $insCount > 0 );
    return ( $count, $insCount );
}

sub getZipType {
    my ( $self, $file ) = @_;

    my $fileType = 'plain';

    if ( $file =~ /\.zip$/i or $file =~ /\.war$/i or $file =~ /\.jar$/i or $file =~ /\.ear$/i ) {
        $fileType = 'zip';
    }
    elsif ( $file =~ /\.tar$/i ) {
        $fileType = 'tar';
    }
    elsif ( $file =~ /\.tgz$/i or $file =~ /\.tar\.gz$/i ) {
        $fileType = 'tgz';
    }

    return $fileType;
}

sub checkMagicNumber {
    my ( $self, $rootDir, $file, $fileType ) = @_;

    my $checkRet = 1;

    if ( not -f "$rootDir/$file" ) {
        return $checkRet;
    }

    my $magicNumbers = {
        'zip' => "\x50\x4b\x03\x04",
        'tar' => "\x75\x73\x74\x61\x72",
        'tgz' => "\x1f\x8b"
    };

    my $fh = IO::File->new("<$rootDir/$file");
    if ( defined($fh) ) {
        my $magicBytes = '';

        if ( $fileType eq 'zip' ) {
            sysread( $fh, $magicBytes, 4 );
        }
        elsif ( $fileType eq 'tar' ) {
            my $tmp;
            sysread( $fh, $tmp,        257 );
            sysread( $fh, $magicBytes, 5 );
        }
        elsif ( $fileType eq 'tgz' ) {
            sysread( $fh, $magicBytes, 2 );
        }
        else {
            return $checkRet;
        }

        if ( $magicBytes ne $magicNumbers->{$fileType} ) {
            print("WARN: file $file is not a $fileType file, wrong magic number, executable archive not supported.\n");
            $checkRet = 0;
        }
    }

    return $checkRet;
}

sub findFilesInDir {
    my ( $self, $rootDir, $cwd, $pkgFiles, $rplOrgFiles, $cfgFiles ) = @_;

    my $env       = $self->{envName};
    my $charset   = $self->{charset};
    my $followZip = $self->{followZip};
    my $followTar = $self->{followTar};
    my $pureDir   = $self->{pureDir};

    my @dirs = ( $cwd . '/' );

    my ( $dir, $file );
    while ( $dir = pop(@dirs) ) {
        local *DH;
        if ( !opendir( DH, $dir ) ) {
            die("ERROR: Cannot opendir $dir: $! $^E");
            next;
        }
        foreach ( readdir(DH) ) {
            if ( $_ eq '.' || $_ eq '..' ) {
                next;
            }
            $file = $dir . $_;
            if ( !-l $file && -d $file ) {
                $file .= '/';
                push( @dirs, $file );
            }

            if ( $file =~ /\.$suffix(\/|$)/ ) {
                $file =~ s/\.$suffix\/.*$/\.$suffix\//;
                $file =~ s/$rootDir\///;

                $cfgFiles->{$file} = 1;

                my $orgFile = $file;
                if ( $orgFile =~ s/(\.$env\.[^\/]*?)\.$suffix\/.*$/\//i ) {
                    $rplOrgFiles->{$orgFile} = 1;
                    $rplOrgFiles->{"$orgFile$1"} = 2;
                }
                elsif ( $orgFile =~ s/(\.$env\.[^\/]*?)\.$suffix$//i ) {
                    $rplOrgFiles->{$orgFile} = 1;
                    $rplOrgFiles->{"$orgFile$1"} = 2;
                }
                elsif ( $orgFile =~ s/(\.$env)\.$suffix\/.*$/\//i ) {
                    $rplOrgFiles->{$orgFile} = 1;
                    $rplOrgFiles->{"$orgFile$1"} = 2;
                }
                elsif ( $orgFile =~ s/(\.$env)\.$suffix$//i ) {
                    $rplOrgFiles->{$orgFile} = 1;
                    $rplOrgFiles->{"$orgFile$1"} = 2;
                }
            }
            elsif ( $pureDir ne 1 ) {
                my $zipType = $self->getZipType($file);
                if ( $zipType ne 'plain' and $self->checkMagicNumber( $rootDir, $file, $zipType ) ) {
                    $self->findFilesInZip( $rootDir, "$file/", $file, $zipType, $pkgFiles, $rplOrgFiles, $cfgFiles );
                }
            }
        }
        closedir(DH);
    }
}

sub checkAndRecordFile {
    my ( $self, $rootDir, $preName, $name, $filePath, $pkgFiles, $rplOrgFiles, $cfgFiles ) = @_;

    my $env       = $self->{envName};
    my $charset   = $self->{charset};
    my $followZip = $self->{followZip};
    my $followTar = $self->{followTar};

    my $parentZipType = $self->getZipType($filePath);
    my $zipType       = $self->getZipType($name);

    if ( $zipType ne 'plain' ) {
        if ( ( $zipType eq 'zip' and $followZip == 1 ) or ( ( $zipType eq 'tgz' or $zipType eq 'tar' ) and $followTar == 1 ) ) {
            my $pathInZip = $name;

            my $tmp       = File::Temp->new( DIR => $TMPDIR, CLEANUP => 1 );
            my $zipTmpDir = $tmp->newdir( DIR => $TMPDIR, CLEANUP => 1 );

            my $filePathEsc = DeployUtils->escapeQuote($filePath);
            my $nameEsc     = DeployUtils->escapeQuote($name);

            my $unzipCmd;
            if ( $parentZipType eq 'zip' ) {
                $unzipCmd = sprintf( qq{unzip -qo -d "%s" "%s" "%s" >/dev/null}, $zipTmpDir, $filePathEsc, $nameEsc );
            }
            elsif ( $parentZipType eq 'tgz' ) {
                $unzipCmd = sprintf( qq{tar -C "%s" -xzvf "%s" "%s" >/dev/null}, $zipTmpDir, $filePathEsc, $nameEsc );
            }
            elsif ( $parentZipType eq 'tar' ) {
                $unzipCmd = sprintf( qq{tar -C "%s" -xvf "%s" "%s" >/dev/null}, $zipTmpDir, $filePathEsc, $nameEsc );
            }

            my $unzipRet = DeployUtils->execmd($unzipCmd);
            if ( $unzipRet eq 0 ) {
                $self->findFilesInZip( $rootDir, "$preName$name/", "$zipTmpDir/$name", $zipType, $pkgFiles, $rplOrgFiles, $cfgFiles );
            }
            else {
                $self->{hasError} = $self->{hasError} + 1;
                print("ERROR: unzip file $preName$name failed.\n");
            }
        }
    }
    else {
        if ( $name =~ /\.$suffix(\/|$)/ and $name !~ /\/$/ ) {
            my $prettyPreName = $preName;
            $name          =~ s/\.$suffix\/.*$/\.$suffix\//;
            $prettyPreName =~ s/^$rootDir\///;
            $cfgFiles->{"$prettyPreName$name"} = 1;

            my $orgName = $name;
            if ( $orgName =~ s/(\.$env\.[^\/]?)\.$suffix\/.*$/\//i ) {
                $rplOrgFiles->{"$prettyPreName$orgName"}   = 1;
                $rplOrgFiles->{"$prettyPreName$orgName$1"} = 2;
            }
            elsif ( $orgName =~ s/(\.$env\.[^\/]?)\.$suffix$//i ) {
                $rplOrgFiles->{"$prettyPreName$orgName"}   = 1;
                $rplOrgFiles->{"$prettyPreName$orgName$1"} = 2;
            }
            elsif ( $orgName =~ s/(\.$env)\.$suffix\/.*$/\//i ) {
                $rplOrgFiles->{"$prettyPreName$orgName"}   = 1;
                $rplOrgFiles->{"$prettyPreName$orgName$1"} = 2;
            }
            elsif ( $orgName =~ s/(\.$env)\.$suffix$//i ) {
                $rplOrgFiles->{"$prettyPreName$orgName"}   = 1;
                $rplOrgFiles->{"$prettyPreName$orgName$1"} = 2;
            }
        }
    }

}

sub findFilesInZip {
    my ( $self, $rootDir, $preName, $filePath, $zipType, $pkgFiles, $rplOrgFiles, $cfgFiles ) = @_;

    my $env       = $self->{envName};
    my $charset   = $self->{charset};
    my $followZip = $self->{followZip};
    my $followTar = $self->{followTar};

    my $pkgPath = $preName;
    $pkgPath =~ s/$rootDir\///;
    $pkgPath =~ s/\/$//;
    $pkgFiles->{$pkgPath} = 1;

    printf( "INFO: try to find $suffix resource in pkg %s.\n", $pkgPath );

    if ( $self->checkMagicNumber( '', $filePath, $zipType ) == 0 ) {
        return;
    }

    if ( $zipType eq 'zip' ) {
        my $cmd = sprintf( "zipinfo -1 '%s'", $filePath );

        my $line;

        my $pipe;
        my $exitCode = 0;
        my $pid      = open( $pipe, "$cmd |" );
        if ( defined($pid) ) {
            while ( $line = <$pipe> ) {
                chomp($line);
                $self->checkAndRecordFile( $rootDir, $preName, $line, $filePath, $pkgFiles, $rplOrgFiles, $cfgFiles );
            }

            #waitpid( $pid, 0 );
            #$exitCode = $?;
            close($pipe);
            $exitCode = $?;
        }

        if ( not defined($pid) or $exitCode != 0 ) {
            $self->{hasError} = $self->{hasError} + 1;
            print("ERROR: read zip content failed:$pkgPath, $!\n");
        }

        #use perl IO::Uncompress.Unzip to read zip entry
        #my $fh = IO::File->new("<$filePath");
        #return if ( not defined($fh) );
        #
        #my $len = -s $filePath;
        #my $unzip = new IO::Uncompress::Unzip( $fh, InputLength => $len ) or die("ERROR: Cannot open pkg $pkgPath $!\n");
        #my $status;
        #
        #for ( $status = 1 ; $status > 0 and defined($unzip) ; $status = $unzip->nextStream() ) {
        #    my $header = $unzip->getHeaderInfo();
        #
        #    #print("DEBUG:zip:$pkgPath header-------------------------------------\n");
        #    #print Dumper $header;
        #    #print("DEBUG:zip header end=================================\n");
        #
        #    if ( not defined($header) ) {
        #
        #        #printf("DEBUG: $preName %s\n", Encode::encode( 'utf-8', Encode::decode( $charset, $header->{Name} ) ) );
        #        last();
        #    }
        #
        #    my $name = $header->{Name};
        #
        #    $self->checkAndRecordFile( $rootDir, $env, $preName, $name, $filePath, $pkgFiles, $rplOrgFiles, $cfgFiles, $charset, $followZip, $followTar );
        #
        #    last if $status < 0;
        #}
        #
        #if ( defined($unzip) ) {
        #    $unzip->close();
        #}
        #
        #$fh->close();
        #
        #if ( $status < 0 ) {
        #    return;
        #}
    }
    elsif ( $zipType eq 'tar' or $zipType eq 'tgz' ) {
        my $fileSize = -s $filePath;
        if ( $fileSize >= 128 ) {
            my $cmd = sprintf( "tar -tf '%s'", $filePath );
            if ( $zipType eq 'tgz' ) {
                $cmd = sprintf( "tar -tzf '%s'", $filePath );
            }

            my $line;

            my $pipe;
            my $exitCode = 0;
            my $pid      = open( $pipe, "$cmd |" );
            if ( defined($pid) ) {
                while ( $line = <$pipe> ) {
                    chomp($line);
                    $self->checkAndRecordFile( $rootDir, $preName, $line, $filePath, $pkgFiles, $rplOrgFiles, $cfgFiles );
                }

                #waitpid( $pid, 0 );
                #$exitCode = $?;

                close($pipe);
                $exitCode = $?;
            }

            if ( not defined($pid) or $exitCode != 0 ) {
                $self->{hasError} = $self->{hasError} + 1;
                print("ERROR: read tar content failed:$pkgPath, $!\n");
            }
        }
    }
}

sub convertInsCfgListCharset {
    my ( $self, $insCfgList, $encoding ) = @_;

    my $insCfgMaps = {};

    foreach my $insInfo (@$insCfgList) {
        my $insCfgMap = $insInfo->{autoCfg};
        if ( defined($insCfgMap) ) {
            $insCfgMap = $self->convertCfgMapCharset( $insCfgMap, $encoding );
        }
    }
}

sub convertCfgMapCharset {
    my ( $self, $cfgMap, $encoding ) = @_;

    if ( $encoding ne 'utf8' and $encoding ne 'utf-8' ) {
        my ( $key, $keyEncode, $val );
        foreach $key ( keys %$cfgMap ) {
            $keyEncode            = Encode::encode( $encoding, Encode::decode( 'utf-8', $key ) );
            $val                  = Encode::encode( $encoding, Encode::decode( 'utf-8', $cfgMap->{$key} ) );
            $cfgMap->{$keyEncode} = $val;
        }
    }

    return $cfgMap;
}

sub removeEmptyDir {
    my ( $self, $rootPath, $subPath ) = @_;
    while ( $subPath ne $rootPath ) {
        last if ( not rmdir($subPath) );
        $subPath = dirname($subPath);
    }
}

sub updateConfigInZip {
    my ( $self, $autoCfgDocRoot, $cwd, $preZipDir, $pkgFiles, $rplOrgFiles, $dirsMap, $insInfo ) = @_;

    my $charset           = $self->{charset};
    my $env               = $self->{envName};
    my $packCfgMap        = $self->{packCfgMap};
    my $cleanAutoCfgFiles = $self->{cleanAutoCfgFiles};
    my $checkOrg          = $self->{checkOrg};

    my $insCfgMap = {};
    if ( defined($insInfo) ) {
        my $insCfgMaps = $self->{insCfgMaps};
        $insCfgMap = $insCfgMaps->{ $insInfo->{uniqName} };
    }

    my $zipType = $self->getZipType($preZipDir);

    if ( $self->checkMagicNumber( '', $preZipDir, $zipType ) == 0 ) {
        return;
    }

    my $subFiles = $self->getAllSubFiles( $dirsMap, $cwd, $pkgFiles );

    my $unzipedMap = {};

    my $diffCfgCount    = 0;
    my $diffInsCfgCount = 0;

    my $tmp       = File::Temp->new( DIR => $TMPDIR, CLEANUP => 1 );
    my $zipTmpDir = $tmp->newdir( DIR => $TMPDIR, CLEANUP => 1 );

    my $preZipDirEsc = DeployUtils->escapeQuote($preZipDir);

    foreach my $subFile (@$subFiles) {
        my $nextCwd = "$cwd/$subFile";
        if ( not defined($cwd) or $cwd eq '' ) {
            $nextCwd = $subFile;
        }

        my $pathInZip = $subFile;
        if ( $subFile =~ /\/$/ ) {
            $pathInZip = "$subFile*";
        }

        my $pathInZipPat;

        my $unzipCmd;
        if ( $pkgFiles->{$nextCwd} eq 1 ) {
            my $pathInZipEsc = DeployUtils->escapeQuote($pathInZip);

            if ( $zipType eq 'zip' ) {
                $unzipCmd = sprintf( qq{unzip -qo -d "%s" "%s" "%s" >/dev/null}, $zipTmpDir, $preZipDirEsc, $pathInZipEsc );
            }
            elsif ( $zipType eq 'tar' ) {
                $unzipCmd = sprintf( qq{tar -C "%s" -xf "%s" "%s" >/dev/null}, $zipTmpDir, $preZipDirEsc, $pathInZipEsc );
            }
            elsif ( $zipType eq 'tgz' ) {
                $unzipCmd = sprintf( qq{tar -C "%s" -xzf "%s" "%s" >/dev/null}, $zipTmpDir, $preZipDirEsc, $pathInZipEsc );
            }
        }
        else {
            my $lastSlashIdx = rindex( $subFile, '/' );
            if ( $subFile =~ /\// ) {
                $lastSlashIdx = rindex( $subFile, '/', 1 );
            }

            my $firstDotIdx = index( $subFile, '.', $lastSlashIdx );
            my $orgSubFile  = substr( $subFile, 0, $firstDotIdx );

            $pathInZipPat = "$orgSubFile*";
            if ( $subFile =~ /\/$/ ) {
                $pathInZipPat = "$orgSubFile*/*";
            }

            if ( $unzipedMap->{$pathInZipPat} != 1 ) {
                my $pathInZipPatEsc = DeployUtils->escapeQuote($pathInZipPat);

                if ( $zipType eq 'zip' ) {
                    $unzipCmd = sprintf( qq{unzip -o -d "%s" "%s" "%s" >/dev/null}, $zipTmpDir, $preZipDirEsc, $pathInZipPatEsc );
                }
                elsif ( $zipType eq 'tar' ) {
                    $unzipCmd = sprintf( qq{tar -C "%s" -xf "%s" "%s" >/dev/null}, $zipTmpDir, $preZipDirEsc, $pathInZipPatEsc );
                }
                elsif ( $zipType eq 'tgz' ) {
                    $unzipCmd = sprintf( qq{tar -C "%s" -xzf "%s" "%s" >/dev/null}, $zipTmpDir, $preZipDirEsc, $pathInZipPatEsc );
                }
                $unzipedMap->{$pathInZipPat} = 1;
            }
        }

        if ( defined($unzipCmd) ) {

            #print("DEBUG: *-*-*-*-*-*-*-$unzipCmd\n");
            my $rc = DeployUtils->execmd($unzipCmd);
            if ( $rc ne 0 ) {
                print("ERROR: get $pathInZipPat from $preZipDir failed.\n");
                $self->{hasError} = $self->{hasError} + 1;
            }
        }

        my $cfgCount    = 0;
        my $insCfgCount = 0;

        if ( $pkgFiles->{$nextCwd} eq 1 ) {
            ( $cfgCount, $insCfgCount ) = $self->updateConfigInZip( $autoCfgDocRoot, $nextCwd, "$zipTmpDir/$subFile", $pkgFiles, $rplOrgFiles, $dirsMap, $insInfo );
        }
        else {
            if ( defined($insInfo) ) {
                printf( "INFO: auto config file in pkg %s (%s).\n", Encode::encode( 'utf-8', Encode::decode( $charset, $nextCwd ) ), $insInfo->{uniqName} );
            }
            else {
                printf( "INFO: auto config file in pkg %s.\n", Encode::encode( 'utf-8', Encode::decode( $charset, $nextCwd ) ) );
            }

            ( $cfgCount, $insCfgCount ) = $self->replacePlaceHolder( $autoCfgDocRoot, "$zipTmpDir/$subFile", $nextCwd, $rplOrgFiles, $insInfo );
            if ( $cleanAutoCfgFiles == 1 ) {
                my $delZipCmd;
                my $tmpTarDir;

                my $pathInZipEsc = DeployUtils->escapeQuote($pathInZip);

                if ( $zipType eq 'zip' ) {
                    $delZipCmd = sprintf( qq{zip -qd "%s" "%s" /dev/null}, $preZipDirEsc, $pathInZipEsc );
                }
                elsif ( $zipType eq 'tar' ) {
                    $delZipCmd = sprintf( qq{tar -f "%s" --delete "%s" >/dev/null}, $preZipDirEsc, $pathInZipEsc );
                }
                elsif ( $zipType eq 'tgz' ) {
                    $tmpTarDir = $tmp->new( DIR => $TMPDIR, CLEANUP => 1, SUFFIX => '.tar' );
                    $delZipCmd = sprintf( qq{gunzip -f -c "%s" > '$tmpTarDir' && tar -f '$tmpTarDir' --delete "%s" && gzip -f -c '$tmpTarDir' > "%s"}, $preZipDirEsc, $pathInZipEsc, $preZipDirEsc );
                }

                #print("DEBUG:=-=-=-=-=-=-=-=-=$delZipCmd\n");
                my $rc = DeployUtils->execmd($delZipCmd);
                if ( $rc ne 0 ) {
                    print("WARN: delete file($pathInZip) in pkg($preZipDir) failed, maybe file not exists, error:$!\n");
                }
            }
        }
        $diffCfgCount    = $diffCfgCount + $cfgCount;
        $diffInsCfgCount = $diffInsCfgCount + $insCfgCount;
    }

    if ( $diffCfgCount > 0 or $diffInsCfgCount > 0 ) {
        my $zipCmd;
        my $tmpTarDir;
        my $rc = 0;

        if ( $zipType eq 'zip' ) {
            my $cwd = getcwd();
            chdir($zipTmpDir);

            find(
                {
                    wanted => sub {
                        my $aFile = $_;
                        if ( -f $aFile or -l $aFile ) {
                            my $fileName = $File::Find::name;
                            $fileName = substr( $fileName, 2 );

                            my $fileNameEsc = DeployUtils->escapeQuote($fileName);

                            my $aZipCmd;
                            if ( $self->getZipType($aFile) eq 'zip' ) {
                                $aZipCmd = sprintf( qq{cd '%s' && zip -q0 "%s" "%s" >/dev/null}, $zipTmpDir, $preZipDirEsc, $fileNameEsc );
                            }
                            else {
                                $aZipCmd = sprintf( qq{cd '%s' && zip -q "%s" "%s" >/dev/null}, $zipTmpDir, $preZipDirEsc, $fileNameEsc );
                            }

                            if ( $rc eq 0 ) {

                                #print("DEBUG: -*-*-*-*$aZipCmd\n");
                                $rc = DeployUtils->execmd($aZipCmd);
                            }
                        }
                    },
                    follow => 0
                },
                '.'
            );

            chdir($cwd);
        }
        elsif ( $zipType eq 'tar' ) {
            $zipCmd = sprintf( qq{cd '%s' && tar -rf "%s" * >/dev/null}, $zipTmpDir, $preZipDirEsc );
        }
        elsif ( $zipType eq 'tgz' ) {
            $tmpTarDir = $tmp->new( DIR => $TMPDIR, CLEANUP => 1, SUFFIX => '.tar' );
            $zipCmd    = sprintf( qq{gunzip -f -c "%s" > '$tmpTarDir' && cd "%s" && tar -rf '$tmpTarDir' * && gzip -f -c '$tmpTarDir' > "%s"}, $preZipDirEsc, $zipTmpDir, $preZipDirEsc );
        }

        if ( $zipType ne 'zip' ) {
            $rc = DeployUtils->execmd($zipCmd);
        }

        if ( $rc ne 0 ) {
            print("ERROR: update config to $preZipDir failed.\n");
            $self->{hasError} = $self->{hasError} + 1;
        }
    }

    return ( $diffCfgCount, $diffInsCfgCount );
}

sub updateConfig {
    my ( $self, $autoCfgDocRoot, $cwd, $pkgFiles, $rplOrgFiles, $dirsMap ) = @_;

    my $charset           = $self->{charset};
    my $env               = $self->{envName};
    my $insCfgList        = $self->{insCfgList};
    my $packCfgMap        = $self->{packCfgMap};
    my $insCfgMaps        = $self->{insCfgMaps};
    my $cleanAutoCfgFiles = $self->{cleanAutoCfgFiles};
    my $checkOrg          = $self->{checkOrg};

    my $subFiles = $self->getAllSubFiles( $dirsMap, $cwd, $pkgFiles );

    #print("DEBUG: sub files for dir:$cwd===================\n");
    #print Dumper $subFiles;
    #print("DEBUG: sub fiels for dir:$cwd-------------------\n");

    foreach my $subFile (@$subFiles) {
        my $nextCwd = "$cwd/$subFile";
        if ( not defined($cwd) or $cwd eq '' ) {
            $nextCwd = $subFile;
        }

        if ( $pkgFiles->{$nextCwd} eq 1 ) {
            my $cfgZipPath = $nextCwd;

            #my $instance;

            my $diffInsCount = 0;
            foreach my $insInfo (@$insCfgList) {
                my $insUniqName = $insInfo->{uniqName};
                my $insName     = $insInfo->{nodeName};
                my $insHost     = $insInfo->{host};

                my $insCfgZipPath = "$autoCfgDocRoot.ins/$insUniqName/$cfgZipPath";
                my $insCfgMap     = $insCfgMaps->{$insUniqName};

                #如果没有定义instance的key value，则判断包下是否有整体替换的instance配置文件
                my $hasInsCfg = 0;
                if ($insCfgMap) {
                    $hasInsCfg = 1;
                }
                else {
                    my $allCfgFilesInZip = $self->getAllSubFiles( $dirsMap, $nextCwd );
                    foreach my $cfgFileInZip (@$allCfgFilesInZip) {

                        #if ( $cfgFileInZip =~ /\.$env\.$instance\.$suffix(\/|$)/i ) {
                        if ( $cfgFileInZip =~ /\.$env\.(.+)\.$suffix(\/|$)/i ) {
                            my $expectIns = lc($1);    #期望是实例唯一名
                            if ( $expectIns eq $insUniqName ) {
                                $hasInsCfg = 1;
                            }
                            elsif ( $expectIns eq $insHost ) {
                                if ( $insInfo->{hostConflictCount} > 0 ) {
                                    $self->{hasError} = $self->{hasError} + 1;
                                    print("ERROR: Instance ip($insHost) not unique, can not auto config $cfgFileInZip.\n");
                                }
                                else {
                                    $hasInsCfg = 1;
                                }
                            }
                            elsif ( $expectIns eq $insName ) {
                                if ( $insInfo->{nameConflictCount} > 0 ) {
                                    $self->{hasError} = $self->{hasError} + 1;
                                    print("ERROR: Instance name($insName) not unique, can not auto config $cfgFileInZip.\n");
                                }
                                else {
                                    $hasInsCfg = 1;
                                }
                            }
                            elsif ( not defined( $insCfgMaps->{ lc($expectIns) } ) ) {
                                $self->{hasError} = $self->{hasError} + 1;
                                print("ERROR: Instance identifier($expectIns) that substract from $cfgFileInZip not exists.\n");
                            }

                            if ( $hasInsCfg == 1 ) {
                                last;
                            }
                        }
                    }
                }

                if ($hasInsCfg) {
                    DeployUtils->copyTree( "$autoCfgDocRoot/$cfgZipPath", $insCfgZipPath );
                    my ( $cfgCount, $insCfgCount ) = $self->updateConfigInZip( $autoCfgDocRoot, $nextCwd, $insCfgZipPath, $pkgFiles, $rplOrgFiles, $dirsMap, $insInfo );
                    if ( $insCfgCount == 0 ) {
                        rmtree($insCfgZipPath);
                        $self->removeEmptyDir( "$autoCfgDocRoot.ins/$insUniqName", dirname($insCfgZipPath) );
                    }
                    else {
                        $diffInsCount = $diffInsCount + 1;
                    }
                }
            }

            #如果是包，则根据实例差异配置进行拷贝并进行修改
            if ( $diffInsCount < scalar(@$insCfgList) or scalar(@$insCfgList) == 0 ) {
                $self->updateConfigInZip( $autoCfgDocRoot, $nextCwd, "$autoCfgDocRoot/$nextCwd", $pkgFiles, $rplOrgFiles, $dirsMap, undef );
            }
        }
        else {
            my $cfgFile     = $nextCwd;
            my $cfgFilePath = "$autoCfgDocRoot/$cfgFile";

            #my $instance;
            my $diffInsCount = 0;
            foreach my $insInfo (@$insCfgList) {
                my $insUniqName = $insInfo->{uniqName};
                my $insName     = $insInfo->{nodeName};
                my $insHost     = $insInfo->{host};

                my $insCfgFilePath = "$autoCfgDocRoot.ins/$insUniqName/$cfgFile";
                my $insCfgMap      = $insCfgMaps->{$insUniqName};

                my $expectIns;

                #如果是实例差异配置，则把配置文件拷贝一份到实例差异目录并进行修改
                #if ( $cfgFile =~ /\.$env\.$instance\.$suffix(\/|$)/i ) {
                if ( $cfgFile =~ /\.$env\.(.+)\.$suffix(\/|$)/i ) {
                    $expectIns = lc($1);

                    if ( $expectIns eq $insHost ) {
                        if ( $insInfo->{hostConflictCount} > 0 ) {
                            $self->{hasError} = $self->{hasError} + 1;
                            print("ERROR: Instance ip($insHost) not unique, can not auto config $cfgFile.\n");
                            next;
                        }
                    }
                    elsif ( $expectIns eq $insName ) {
                        if ( $insInfo->{nameConflictCount} > 0 ) {
                            $self->{hasError} = $self->{hasError} + 1;
                            print("ERROR: Instance name($insName) not unique, can not auto config $cfgFile.\n");
                            next;
                        }
                    }
                    elsif ( not $expectIns eq $insUniqName ) {
                        if ( not defined( $insCfgMaps->{$expectIns} ) ) {
                            $self->{hasError} = $self->{hasError} + 1;
                            print("ERROR: Instance identifier($expectIns) that substract from $cfgFile not exists.\n");
                        }
                        next;
                    }

                    $insInfo->{expectIns} = $expectIns;
                }

                if ( $insCfgMap or defined($expectIns) ) {
                    if ( not defined($expectIns) ) {
                        $expectIns = $insUniqName;
                    }

                    printf( "INFO: auto config file %s (%s).\n", Encode::encode( 'utf-8', Encode::decode( $charset, $cfgFile ) ), $expectIns );

                    my $src = $cfgFilePath;
                    $src =~ s/\/$//;
                    my $dest = $insCfgFilePath;
                    $dest =~ s/\/$//;

                    DeployUtils->copyTree( $src, $dest );

                    my ( $cfgCount, $insCfgCount ) = $self->replacePlaceHolder( $autoCfgDocRoot, $insCfgFilePath, $cfgFile, $rplOrgFiles, $insInfo );

                    if ( $insCfgCount == 0 ) {

                        #如果没有任何实例差异，则删除实例副本
                        rmtree($insCfgFilePath);
                        $insCfgFilePath =~ s/\.$env\.$expectIns\.$suffix//i;
                        $insCfgFilePath =~ s/\.$env\.$suffix//i;
                        $insCfgFilePath =~ s/\.$suffix//i;
                        rmtree($insCfgFilePath);

                        $self->removeEmptyDir( "$autoCfgDocRoot.ins", dirname($insCfgFilePath) );
                    }
                    else {
                        $diffInsCount = $diffInsCount + 1;
                    }
                }
            }

            if ( $diffInsCount < scalar(@$insCfgList) or scalar(@$insCfgList) == 0 ) {
                printf( "INFO: auto config file %s.\n", Encode::encode( 'utf-8', Encode::decode( $charset, $cfgFile ) ) );
                $self->replacePlaceHolder( $autoCfgDocRoot, $cfgFilePath, $cfgFile, $rplOrgFiles, undef );
            }

            if ($cleanAutoCfgFiles) {
                rmtree($cfgFilePath);
                rmtree("$cfgFilePath.md5");
            }
        }
    }
}

sub config {
    my ($self) = @_;

    my $orgCfgFiles       = $self->{orgCfgFiles};
    my $version           = $self->{version};
    my $envName           = $self->{envName};
    my $charset           = $self->{charset};
    my $followZip         = $self->{followZip};
    my $cleanAutoCfgFiles = $self->{cleanAutoCfgFiles};
    my $followTar         = $self->{followTar};
    my $checkOrg          = $self->{checkOrg};
    my $pureDir           = $self->{pureDir};
    my $md5Check          = $self->{md5Check};

    my $packCfgMap      = $self->{autoCfg};
    my $insCfgList      = $self->{insCfgList};
    my $insCfgMaps      = $self->{insCfgMaps};
    my $insCount        = $self->{insCount};
    my $autoCfgDocRoots = $self->{autoCfgDocRoots};

    foreach my $autoCfgDocRoot (@$autoCfgDocRoots) {
        if ( -d $autoCfgDocRoot ) {

            print("INFO: begin to auto config $autoCfgDocRoot========.\n");

            #清理实例差异配置
            for my $insInfo (@$insCfgList) {
                my $insUniqName = $insInfo->{uniqName};
                if ( -d "$autoCfgDocRoot.ins/$insUniqName" ) {
                    rmtree("$autoCfgDocRoot.ins/$insUniqName");
                }
            }

            my $rplOrgFiles = {};
            my $pkgFiles    = {};
            my $cfgFiles;
            my $dbSrc = $self->{dbSrc};
            if ( $autoCfgDocRoot !~ /^$dbSrc\// ) {
                $cfgFiles = $orgCfgFiles;
            }

            if ( not defined($cfgFiles) or scalar(@$cfgFiles) == 0 ) {
                $cfgFiles = [];
                print("INFO:config files list not provided.\n");
                print("INFO:begin to find *.$suffix files--------.\n");

                my $cfgFilesFinded = {};
                $self->findFilesInDir( $autoCfgDocRoot, $autoCfgDocRoot, $pkgFiles, $rplOrgFiles, $cfgFilesFinded );

                @$cfgFiles = keys(%$cfgFilesFinded);

                if ( scalar(@$cfgFiles) > 0 ) {
                    print("INFO:find config files to be auto config:\n");
                    foreach my $cfgFile ( sort sortByLen (@$cfgFiles) ) {
                        print( '->', Encode::encode( 'utf-8', Encode::decode( $charset, $cfgFile ) ), "\n" );
                    }
                }
                else {
                    print("INFO:can not find any *.$suffix files.\n");
                }
            }
            else {
                $cfgFiles = $self->parsePreDefinedCfgFiles( $autoCfgDocRoot, $cfgFiles, $pkgFiles, $rplOrgFiles );
            }

            print("INFO: find $suffix finished--------.\n");

            #print("DEBUG:all $suffix files==========\n");
            #print Dumper $pkgFiles;
            my $dirsMap = $self->toDirsMap($cfgFiles);

            #print Dumper $dirsMap;
            #exit(1);

            if ( $self->{hasError} == 0 ) {
                $self->updateConfig( $autoCfgDocRoot, '', $pkgFiles, $rplOrgFiles, $dirsMap );

                eval {
                    my $md5ListFileName = $FileUtils::md5ListFileName;
                    if ( defined($md5Check) and $md5Check == 1 ) {
                        FileUtils::genMd5($autoCfgDocRoot);
                        if ( -d "$autoCfgDocRoot.ins" ) {
                            foreach my $insDir ( glob("$autoCfgDocRoot.ins/*") ) {
                                FileUtils::genMd5($insDir);
                                $self->mergeMd5SumList( "$autoCfgDocRoot/$md5ListFileName", "$insDir/$md5ListFileName" );
                            }
                        }
                    }
                };
                if ($@) {
                    $self->{hasError} = $self->{hasError} + 1;
                    my $errMsg = $@;
                    $errMsg =~ s/ at\s*.*$//;
                    print($errMsg );
                }

                print("INFO: $suffix $autoCfgDocRoot finished========.\n");
            }
        }
    }

    return $self->{hasError};
}

1;

