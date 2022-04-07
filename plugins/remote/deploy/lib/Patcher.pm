#!/usr/bin/perl
use strict;

package Patcher;

use IO::File;
use FindBin;
use lib "$FindBin::Bin";
use Cwd 'abs_path';
use File::Basename;
use File::Path;
use File::Temp;
use File::Copy;
use POSIX;

sub new {
    my ( $type, $homePath, $backupDir, $backupCount, $backupLastDays ) = @_;
    my $self     = {};
    my $homePath = abs_path("$FindBin::Bin/..");
    my @uname    = uname();
    my $osType   = 'unix';
    $osType = 'windows' if ( $uname[0] =~ /Windows/i );

    $self->{homePath}  = $homePath;
    $self->{osType}    = $osType;
    $self->{backupDir} = $backupDir;

    $self->{backupCount} = 5;
    if ( defined($backupCount) ) {
        $self->{backupCount} = $backupCount;
    }

    $self->{backupLastDays} = 90;
    if ( defined($backupLastDays) ) {
        $self->{backupLastDays} = int($backupLastDays);
    }

    return bless( $self, $type );
}

sub _writePatchDesc {
    my ( $ins, $version, $packFile, $targetType, $targetDir, $backupType, $backupFile ) = @_;
    my $patchDescFile = "$backupFile.desc.txt";
    my $fh            = IO::File->new(">$patchDescFile");

    if ( defined($fh) ) {
        print $fh ("target=$targetDir\n");
        print $fh ("targetType=$targetType\n");
        print $fh ("version=$version\n");
        print $fh ("instance=$ins\n");
        print $fh ("packFile=$packFile\n");
        print $fh ("backupType=$backupType\n");
        print $fh ("backupFile=$backupFile\n");

        $fh->close();
        return 0;
    }

    return -1;
}

sub _walkDir {
    my ( $startPath, $callback ) = @_;

    my $status = 0;
    if ( not -d $startPath ) {
        die("ERROR: destination path:$startPath not a directory.");
    }
    my $curDir = getcwd();
    if ( not chdir($startPath) ) {
        die("ERROR: can not list dir:$startPath.");
    }

    my @dirs = ("./");
    my ( $dir, $file, @statInfo );

    while ( $dir = pop(@dirs) ) {
        local *DH;
        if ( $dir eq "./" ) {
            if ( !opendir( DH, $dir ) ) {
                chdir($curDir);
                die("ERROR: Cannot opendir $startPath: $! $^E");
                return;
            }
            $dir = "";
        }
        else {
            if ( !opendir( DH, $dir ) ) {
                chdir($curDir);
                die("ERROR: Cannot opendir $dir: $! $^E");
                return;
            }
        }

        foreach ( readdir(DH) ) {
            if ( $_ eq "." || $_ eq ".." || $_ eq ".svn" || $_ eq ".git" ) {
                next;
            }

            $file = $dir . $_;
            if ( !-l $file && -d _ ) {
                $file .= "/";
                push( @dirs, $file );
            }
            elsif ( -f $file or -l $file ) {
                my $ret = &$callback($file);
                if ( $ret != 0 ) {
                    die("EROR: backup $file failed.");
                }
            }
        }
        closedir(DH);
    }
    chdir($curDir);
}

sub _backupFiles {
    my ( $self, $reader, $backupFile, $packFile, $regexp ) = @_;
    my $file;
    while ( my $line = <$reader> ) {

        chomp($line);
        if ( not defined($regexp) ) {
            $file = $line;
        }
        elsif ( $line =~ /$regexp/ ) {
            $file = $1;
        }
        else {
            next;
        }

        if ( -e $file ) {
            my $status = system("tar -cvf '$backupFile' '$file'");

            if ( $status != 0 ) {
                print("ERROR: tar '$file' to $backupFile failed.\n");
                unlink($backupFile);
                return -1;
            }
        }
    }
}

sub _backupPackFiles {
    my ( $self, $ins, $version, $backupFile, $packFile, $target ) = @_;

    my $packFilePath = $packFile;

    my $osType = $self->{osType};
    my $reader;
    if ( -d $packFilePath ) {
        my $cb = sub {
            my ($file) = @_;
            my $status = -1;
            if ( $osType eq 'windows' ) {
                $status = system("7z.exec a \"$backupFile\" -ttar \"$file\"");
            }
            else {
                $status = system("tar -cvf '$backupFile' '$file'");
            }

            if ( $status != 0 ) {
                print("ERROR: tar '$file' to '$backupFile' failed.\n");
                unlink($backupFile);
                return -1;
            }

        };

        eval { _walkDir( $target, $cb ); };
        if ($@) {
            print("$@\n");
            return -1;
        }
    }
    elsif ( $packFilePath =~ /\.(zip|war|jar|ear)$/i ) {
        if ( $osType eq 'windows' ) {
            open( $reader, "7z.exe x -l -tzip \"$packFilePath\" |" );
        }
        else {
            open( $reader, "zip -t '$packFilePath' |" );
        }

        $self->_backupFiles( $reader, $backupFile, $packFile, '^testing:\s+(.*?)\s+OK\s*$' );
    }
    elsif ( $packFilePath =~ /\.tar$/i ) {
        if ( $osType eq 'windows' ) {
            open( $reader, "7z.exe x -l -ttar \"$packFilePath\" |" );
        }
        else {
            open( $reader, "tar -tvf '$packFilePath' |" );
        }
        $self->_backupFiles( $reader, $backupFile, $packFile, '\d\d:\d\d\s+(.*?)\s*$' );
    }
    elsif ( $packFilePath =~ /\.(tar\.gz|tgz)/i ) {
        if ( $osType eq 'windows' ) {
            open( $reader, "7z.exe x -tgzip -so \"$packFilePath\" | 7z.exe -x -si -ttar -l |" );
        }
        else {
            open( $reader, "gzip -d -c '$packFilePath' | tar -tvf - |" );
        }
        $self->_backupFiles( $reader, $backupFile, $packFile, '\d\d:\d\d\s+(.*?)\s*$' );
    }

    return 0;
}

sub _backupDelFiles {
    my ( $self, $ins, $version, $backupFile, $packFile, $target ) = @_;
    my $patchFile = "$packFile.patch.txt";
    my $osType    = $self->{osType};

    if ( -f $patchFile ) {
        my $fh = IO::File->new("<$patchFile");
        if ( defined($fh) ) {
            my $line;
            while ( $line = <$fh> ) {
                my @items = split( /\s+/, $line );
                if ( $items[0] eq '-' or $items[0] eq '+' ) {
                    my $file = $items[1];
                    $file =~ s/^\///;
                    $file =~ s/\.\.\///;
                    $file =~ s/\/\.\.//;

                    my $status = -1;
                    if ( $osType eq 'windows' ) {
                        $status = system("7z.exec a \"$backupFile\" -ttar \"$file\"");
                    }
                    else {
                        $status = system("tar -cvf '$backupFile' '$file'");
                    }
                    if ( $status != 0 ) {
                        print("ERROR: tar $file to $backupFile failed.\n");
                        unlink($backupFile);
                        return -1;
                    }
                }
            }
            $fh->close();
        }
        else {
            print("ERROR: Can not open patchFile:$patchFile\n");
        }
    }

    return 0;
}

sub backup {
    my ( $self, $ins, $version, $packFile, $target, $backupType ) = @_;
    my $homePath = $self->{homePath};
    my $osType   = $self->{osType};

    my $targetName     = basename($target);
    my $backupDir      = $self->{backupDir} . "/$ins.backup";
    my $backupCount    = int( $self->{backupCount} );
    my $backupLastDays = $self->{backupLastDays};

    mkpath($backupDir) if ( not -e $backupDir );

    my @backupDescFiles;
    if ( $osType eq 'windows' ) {
        @backupDescFiles = glob("\"$backupDir/*.desc.txt\"");
    }
    else {
        @backupDescFiles = glob("$backupDir/*.desc.txt");
    }

    my @sortedBackupDescFiles =
        sort { ( stat($a) )[9] <=> ( stat($b) )[9] } @backupDescFiles;

    my $backupTotalCount = scalar(@sortedBackupDescFiles);

    my $now = time();
    for ( my $i = 0 ; $i < $backupTotalCount - $backupCount ; $i++ ) {
        my $backupDesc = $sortedBackupDescFiles[$i];
        my $backup     = $backupDesc;
        $backup =~ s/\.desc\.txt$//;
        my @info = stat($backup);
        if ( $backupLastDays != -1 and $now - $info[9] > 86400 * $backupLastDays ) {
            if ( unlink($backup) and unlink($backupDesc) ) {
                print("INFO: Remove out dated backup:$backup success.\n");
            }
            else {
                print("ERROR: Remove out dated backup:$backup failed, $!\n");
            }
        }
        else {
            print("INFO: Old backup file:$backup created in $backupLastDays, not full filled the delete rule.\n");
        }
    }

    my $status = 0;
    my $backupFile;

    if ( -f $target ) {
        $backupType = 'fullbackup';
        $backupFile = "$backupDir/$version.$targetName";

        if ( -f $backupFile ) {
            print("INFO: Backup file $backupFile exist, already has been backuped.\n");
            return 0;
        }
        else {
            if ( not copy( $target, $backupFile ) ) {
                $status = -1;
                print("ERROR: copy $target to $backupFile failed.\n");
                unlink($backupFile) if ( -f $backupFile );
            }
            else {
                print("INFO: Backup copy $target to $backupFile success.\n");

                $status = _writePatchDesc( $ins, $version, $packFile, 'file', $target, $backupType, $backupFile );
                if ( $status != 0 ) {
                    print("ERROR: can not write backup desc file to $backupFile.desc.txt.\n");
                    unlink($backupFile) if ( -f $backupFile );
                }
            }
        }
    }
    elsif ( -d $target ) {
        $backupFile = "$backupDir/$version.$targetName.bk.tgz";

        if ( -f $backupFile and $backupType eq 'fullbackup' ) {
            print("INFO: Backup file $backupFile exist, already has been backuped.\n");
        }
        else {
            if ( chdir($target) ) {
                if ( $backupType eq 'fullbackup' ) {
                    if ( $osType eq 'windows' ) {
                        $status = system("7z.exe a -ttar -so . | 7z.exe a -tgzip -si \"$backupFile\"");
                    }
                    else {

                        $status = system("tar -cvf - . | gzip > '$backupFile'");
                    }

                    if ( $status != 0 ) {
                        print("ERROR: tar $target to $backupFile failed.\n");
                        unlink($backupFile) if ( -f $backupFile );
                    }
                    else {
                        print("INFO: Backup tar $target to $backupFile success.\n");
                    }
                }
                else {
                    $status = -1;
                    print("ERROR: deltabackup not supported.\n");

                    #$status = $self->_backupDelFiles( $ins, $version, $backupFile, $packFile, $target );
                    #if ( $status == 0 ) {
                    #    $status = $self->_backupPackFiles( $ins, $version, $backupFile, $packFile, $target );
                    #}
                }

                if ( $status == 0 ) {
                    $status = _writePatchDesc( $ins, $version, $packFile, 'dir', $target, $backupType, $backupFile );
                    if ( $status != 0 ) {
                        print("ERROR: can not write backup desc file to $backupFile.desc.txt.\n");
                        unlink($backupFile) if ( -f $backupFile );
                    }
                }
            }
            else {
                print("ERROR: Can not cd directory $target, backup failed $!\n");
            }
        }
    }
    else {
        print("ERROR: Deploy target path:$target not exists or is not a diectory.\n");
    }

    if ( $status == 0 ) {
        print("INFO: $ins $backupType $target to $backupFile for version $version success.\n");
    }
    else {
        print("ERROR: $ins $backupType $target for $backupFile version $version failed.\n");
    }

    return $status;
}

sub patch {
    my ( $self, $ins, $version, $packFile, $target ) = @_;
    $self->deploy( $ins, $version, $packFile, $target, 0 );
}

sub interpretPathchFile {
    my ( $osType, $packFile ) = @_;
    my $hasError = 0;

    my $patchFile = "$packFile.patch.txt";

    #xxx.patch.txt format:
    #- <filepath> #delete file
    #+ <filepath> <mode> #modify permission
    if ( -f $patchFile ) {
        my $fh = IO::File->new("<$patchFile");
        if ( defined($fh) ) {
            my $line;
            while ( $line = <$fh> ) {
                my @items = split( /\s+/, $line );
                if ( $items[0] eq '-' ) {
                    my $file = $items[1];
                    $file =~ s/^\///;
                    $file =~ s/\.\.\///;
                    $file =~ s/\/\.\.//;
                    if ( -e $file ) {
                        my $count = unlink($file);
                        if ( $count == 0 ) {
                            $hasError = 1;
                            print("ERROR: remove $file failed.");
                        }
                    }
                    else {
                        $hasError = 1;
                        print("ERROR: $file not exists.");
                    }
                }
                elsif ( $items[0] eq '+' and $osType ne 'windows' ) {
                    my $file = $items[1];
                    eval {
                        my $mode = oct( $items[2] );
                        $file =~ s/^\///;
                        $file =~ s/\.\.\///;
                        $file =~ s/\/\.\.//;
                        if ( -e $file ) {
                            my $count = chmod( $mode, $file );
                            if ( $count == 0 ) {
                                $hasError = 1;
                                print("ERROR: chmod $file failed.");
                            }
                        }
                        else {
                            $hasError = 1;
                            print("ERROR: $file not exists.");
                        }
                    };
                }
            }
            $fh->close();
        }
        else {
            $hasError = 1;
            print("ERROR: Can not open patchFile:$patchFile\n");
        }
    }

    if ( $hasError == 0 ) {
        return 1;
    }
    else {
        return 0;
    }
}

sub deploy {
    my ( $self, $ins, $version, $packFile, $target, $fullDeploy ) = @_;
    my $status = 0;

    my $homePath = $self->{homePath};
    my $osType   = $self->{osType};

    if ( -d $target ) {
        if ( chdir($target) ) {

            if ( $fullDeploy == 1 ) {

                #如果是目录式的全量发布，则删除目标目录下的所有子目录和文件
                my $dirH;
                if ( opendir( $dirH, $target ) ) {
                    my $dir;
                    while ( $dir = readdir($dirH) ) {
                        if ( $dir ne '.' and $dir ne '..' ) {
                            if ( -d $dir ) {
                                if ( not rmtree($dir) ) {
                                    $status = -1;
                                    print("ERROR: Remove directory $dir failed, $!\n");
                                    last;
                                }
                            }
                            else {
                                if ( not unlink($dir) ) {
                                    $status = -1;
                                    print("ERROR: Remove file $dir failed, $!\n");
                                    last;
                                }
                            }
                        }
                    }
                }
                else {
                    $status = -1;
                }
            }

            if ( -d $packFile ) {
                print("INFO: Begin copy $packFile to $target...\n");
                if ( $osType eq 'windows' ) {
                    $status = system("xcopy /R /E /Y /I \"$packFile\" .");
                }
                else {
                    $status = system("cp -rf '$packFile/.' ./");
                }
            }
            elsif ( $packFile =~ /\.(zip|war|jar|ear)$/i ) {
                print("INFO: Begin unzip $packFile to $target...\n");
                if ( $osType eq 'windows' ) {
                    $status = system("7z.exe x -aoa -tzip \"$packFile\"");
                }
                else {
                    $status = system("unzip -o '$packFile'");
                }
            }
            elsif ( $packFile =~ /\.tar$/i ) {
                print("INFO: Begin untar $packFile to $target...\n");
                if ( $osType eq 'windows' ) {
                    $status = system("7z.exe x -aoa -ttar \"$packFile\"");
                }
                else {
                    $status = system("tar -xvf '$packFile'");
                }
            }
            elsif ( $packFile =~ /\.(tar\.gz|tgz)/i ) {
                print("INFO: Begin untar $packFile to $target...\n");
                if ( $osType eq 'windows' ) {
                    $status = system("7z.exe x -tgzip -so \"$packFile\" | 7z.exe x -ttar -aoa -si");
                }
                else {
                    $status = system("gzip -c -d '$packFile' | tar -xvf -");
                }
            }

            if ( $status != 0 ) {
                print("ERROR: unzip $packFile to $target failed.\n");
            }

            if ( not interpretPathchFile( $osType, $packFile ) ) {
                $status = 3;
            }
        }
        else {
            print("ERROR: Can not cd directory $target, deploy failed $!\n");
        }
    }
    elsif ( -f $target ) {
        my $ret = 1;

        if ( $fullDeploy == 1 ) {
            if ( copy( $packFile, $target ) ) {
                $ret = 0;
                print("INFO: Copy $packFile to $target success.\n");
            }
            else {
                $ret = 2;
                print("ERROR: Copy $packFile to $target failed, $!\n");
            }
        }
        else {
            print("INFO: Begin merge $packFile to $target...\n");
            my $tmp = File::Temp->new( DIR => "$homePath/tmp", CLEANUP => 1 );
            my $tmpDir = File::Temp->newdir();

            if ( chdir($tmpDir) ) {
                if ( $osType eq 'windows' ) {
                    $ret = system("7z.exe x -tzip -aoa \"$target\"");
                    if ( $ret eq 0 ) {
                        if ( -f $packFile ) {
                            print("INFO: Begin unzip $packFile to tmp dir:$tmpDir.\n");
                            $ret = system("7z.exe x -tzip -aoa \"$packFile\"");
                        }
                        else {
                            print("INFO: Begin copy $packFile to tmp dir:$tmpDir.\n");
                            $ret = system("xcopy /R /E /Y /I \"$packFile\" .");
                        }
                        if ( $ret eq 0 and not interpretPathchFile( $osType, $packFile ) ) {
                            $ret = 3;
                        }
                    }

                    if ( $ret eq 0 ) {
                        if ( unlink($target) ) {
                            print("INFO: Begin zip $tmpDir to application package:$target\n");
                            $ret = system("7z.exe a -tzip \"$target\" .");
                            print("INFO: Update $target success.\n");
                        }
                        else {
                            $ret = 3;
                            print("ERROR: Can not delete file $target, $!\n");
                        }
                    }
                }
                else {
                    print("INFO: Begin unzip application package:$target to tmp dir:$tmpDir...\n");
                    $ret = system("unzip -o -d '$tmpDir' '$target'");
                    if ( $ret eq 0 ) {
                        if ( -f $packFile ) {
                            print("INFO: Begin unzip $packFile to tmp dir:$tmpDir.\n");
                            $ret = system("unzip -o -d '$tmpDir' '$packFile'");
                        }
                        else {
                            print("INFO: Begin copy $packFile to tmp dir:$tmpDir.\n");
                            $ret = system("cp -rf '$packFile/.' ./");
                        }

                        if ( $ret eq 0 and not interpretPathchFile( $osType, $packFile ) ) {
                            $ret = 3;
                        }
                    }

                    if ( $ret eq 0 ) {
                        if ( unlink($target) ) {
                            print("INFO: Begin zip $tmpDir to application package:$target\n");
                            $ret = system("zip -r '$target' .");
                            print("INFO: Update $target success.\n");
                        }
                        else {
                            $ret = 3;
                            print("ERROR: Can not delete file $target, $!\n");
                        }
                    }
                }
            }
            else {
                print("ERROR: Can not cd directory $tmpDir, deploy failed $!\n");
            }

            chdir($homePath);
        }

        if ( $ret eq 0 ) {
            if ( $fullDeploy == 1 ) {
                print("INFO: Deploy $packFile to $target succeed.\n");
            }
            else {
                print("INFO: Patch $packFile to $target succeed.\n");
            }
        }
        else {
            if ( $fullDeploy == 1 ) {
                print("ERROR: Deploy $packFile to $target failed.\n");
            }
            else {
                print("ERROR: Patch $packFile to $target failed.\n");
            }
            $status = $ret;
        }
    }
    else {
        print("ERROR: Deploy target path:$target not exists or is not a diectory.\n");
        $status = -1;
    }

    return $status;
}

sub _getParam {
    my ( $path, $key ) = @_;
    my $value = "";
    my $fh    = IO::File->new("<$path");
    while ( my $line = <$fh> ) {
        $line =~ s/^\s*|\s*$//g;
        my @datas = split( /\s*=\s*/, $line );
        if ( $datas[0] eq "$key" ) {
            $value = $datas[1];
            last;
        }
    }
    $fh->close();
    return $value;
}

sub rollback {
    my ( $self, $ins, $version, $target ) = @_;

    my $homePath  = $self->{homePath};
    my $osType    = $self->{osType};
    my $backupDir = $self->{backupDir} . "/$ins.backup";

    my @backupDescs;
    if ( $osType eq 'windows' ) {
        @backupDescs = glob("\"$backupDir/$version*.desc.txt\"");
    }
    else {
        @backupDescs = glob("$backupDir/$version*.desc.txt");
    }

    my $backupCount = scalar(@backupDescs);

    if ( $backupCount == 0 ) {
        print("ERROR: Can not find any backup files in directory:$backupDir for version:$version.\n");
        print("ERROR: Can not rollback\n");
        return 2;
    }
    if ( $backupCount > 1 ) {
        print("ERROR: There are $backupCount backup files found, but expect only one.\n");
        foreach my $backup (@backupDescs) {
            $backup =~ s/\.desc\.txt$//;
            print("\t$backup\n");
        }
        print("ERROR: Can not rollback\n");
        return 3;
    }
    else {
        my $backup = $backupDescs[0];
        $backup =~ s/\.desc\.txt$//;
        if ( -f $backup ) {
            print("INFO: Use backup $backup to rollback to the state before version:$version\n");
        }
        else {
            print("ERROR: Backup file $backup not exist.\n");
            print("ERROR: Can not rollback\n");
            return 4;
        }
    }

    my $hasBackup = 0;
    my $status    = 0;
    foreach my $backupDesc (@backupDescs) {
        if ( $backupDesc =~ /\.desc\.txt$/ ) {
            $hasBackup = 1;

            my $backup = $backupDesc;
            $backup =~ s/\.desc\.txt$//;

            my $targetPath = _getParam( $backupDesc, 'target' );
            my $targetType = _getParam( $backupDesc, 'targetType' );
            my $backupType = _getParam( $backupDesc, 'backupType' );

            if ( defined($target) and $target ne '' and $targetPath ne $target ) {
                print("ERROR: Backup file:$backup is not backup from $target but $targetPath\n");
                print("ERROR: Can not rollback.\n");
                $status = 5;
                last;
            }

            if ( $targetType eq 'dir' ) {
                chdir("$targetPath");

                if ( $backupType eq 'fullbackup' ) {
                    my $dirH;
                    if ( opendir( $dirH, $targetPath ) ) {
                        my $dir;
                        while ( $dir = readdir($dirH) ) {
                            if ( $dir ne '.' and $dir ne '..' ) {
                                if ( -d $dir ) {
                                    if ( not rmtree($dir) ) {
                                        $status = -1;
                                        print("ERROR: Remove directory $dir failed, $!\n");
                                        last;
                                    }
                                }
                                else {
                                    if ( not unlink($dir) ) {
                                        $status = -1;
                                        print("ERROR: Remove file $dir failed, $!\n");
                                        last;
                                    }
                                }
                            }
                        }
                    }
                    else {
                        $status = -1;
                    }

                    if ( $status == 0 ) {
                        print("INFO: Remove content in application directory:$targetPath success.\n");
                    }
                }

                if ( $status == 0 ) {
                    print("INFO: Begin unzip backup:$backup to application directory:$targetPath...\n");
                    if ( $osType ne 'windows' ) {
                        $status = system("gzip -d -c '$backup' | tar -xvf -");
                    }
                    else {
                        $status = system("7z.exe x -so -tgzip \"$backup\" | 7z.exe x -si -aoa -ttar");
                    }

                    if ( $status == 0 ) {
                        print("INFO: Untar backup:$backup to application directory:$targetPath success.\n");
                    }
                }
            }
            else {
                if ( copy( $backup, $targetPath ) ) {
                    $status = 0;
                    print("INFO: Copy backup:$backup to application directory:$targetPath success.\n");
                }
                else {
                    print("ERROR: Copy backup:$backup to application directory:$targetPath failed, $!\n");
                    $status = 1;
                }
            }

            if ( $status == 0 ) {
                print("INFO: Rollback backup:$backup to application directory:$targetPath succeed.\n");
            }
            else {
                print("ERROR: Rollback backup:$backup to application directory:$targetPath failed.\n");
            }
        }

        if ( $status != 0 ) {
            last;
        }
    }

    if ( $status == 0 ) {
        if ( $hasBackup == 1 ) {
            print("INFO: rollback $ins $version success.\n");
        }
        else {
            $status = -1;
            print("ERROR: no backup for $ins $version, rollback failed.\n");
        }
    }
    else {
        print("ERROR: rollback $ins $version failed.\n");
    }

    return $status;
}

1;

