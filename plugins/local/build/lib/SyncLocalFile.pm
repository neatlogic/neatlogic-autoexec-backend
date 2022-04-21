#!/usr/bin/perl
use strict;

package SyncLocalFile;

use FindBin;
use IO::File;
use File::Path;
use File::Basename;
use Digest::MD5;
use Cwd qw(realpath);
use File::Find;
use File::Copy;
use File::Temp;
use File::Glob qw(bsd_glob);
use Cwd;

use DeployUtils;

our $HAS_ERROR = 0;

sub new {
    my ( $pkg, %args ) = @_;
    my $self = {
        version => $args{version},
        md5     => $args{md5},
        mtime   => $args{mtime},
        backup  => $args{backup},
        tmpDir  => $args{tmpDir}
    };

    if ( not defined( $self->{md5} ) ) {
        $self->{md5} = 0;
    }
    if ( not defined( $self->{mtime} ) ) {
        $self->{mtime} = 0;
    }
    if ( not defined( $self->{backup} ) ) {
        $self->{backup} = 0;
    }
    if ( not defined( $self->{tmpDir} ) or $self->{tmpDir} eq '' ) {
        $self->{tmpDir} = '/tmp';
    }

    $self->{deployUtils} = DeployUtils->new();

    bless( $self, $pkg );

    return $self;
}

sub isExceptMatch {
    my ( $sPrefixs, $ePrefixs, $path ) = @_;

    my ( $sPrefix, $ePrefix );

    foreach $sPrefix (@$sPrefixs) {
        if ( substr( $path, 0, length($sPrefix) ) eq $sPrefix ) {
            return 1;
        }
    }

    foreach $ePrefix (@$ePrefixs) {
        if ( substr( $path, -length($ePrefix) ) eq $ePrefix ) {
            return 1;
        }
    }

    return 0;
}

sub getFileMd5 {
    my ( $self, $filePath ) = @_;

    my $md5Hash = '';

    if ( -f $filePath ) {
        my $fh = new IO::File("<$filePath");

        if ( defined($fh) ) {
            $md5Hash = Digest::MD5->new->addfile(*$fh)->hexdigest();
            $fh->close();
        }
    }

    return $md5Hash;
}

sub mkShadowPath {
    my ( $self, $shadowDir, $targetDir, $relativePath ) = @_;

    return if ( $relativePath eq '' );
    mkpath($shadowDir) if ( not -e $shadowDir );

    my @subdirs = split( '/', $relativePath );
    my $subPath = '';
    my ( $subdir, $shadowPath, $targetPath, @statInfo );

    my $len = scalar(@subdirs);
    for ( my $i = 0 ; $i < $len ; $i++ ) {

        $subdir = $subdirs[$i];

        if ( $subPath ne '' ) {
            $subPath = "$subPath/$subdir";
        }
        else {
            $subPath = $subdir;
        }

        $shadowPath = "$shadowDir/$subPath";
        $targetPath = "$targetDir/$subPath";

        if ( not -e $shadowPath ) {

            #print("debug:mkdir:$shadowPath\n");
            mkdir($shadowPath);
            @statInfo = stat($targetPath);
            chmod( $statInfo[2], $shadowPath );
        }
    }
}

#遍历本地文件时间过程
sub allLocalFiles {
    my ( $self, $startPath, $xPath ) = @_;

    my $outfiles = {};
    my $outdirs  = {};

    my ( @sPrefixs, @ePrefixs );

    if ( defined($xPath) ) {
        my @tmpDirs = split( /\s*,\s*/, $xPath );
        foreach my $tmpdir (@tmpDirs) {
            if ( $tmpdir =~ /\$$/ ) {
                $tmpdir =~ s/\$$//;
                push( @ePrefixs, $tmpdir );
            }
            else {
                push( @sPrefixs, $tmpdir );
            }
        }
    }
    my $sP = \@sPrefixs;
    my $eP = \@ePrefixs;

    if ( not -e $startPath ) {
        $HAS_ERROR = 1;
        die("ERROR: Local path:$startPath not exists or permission deny.");
    }

    if ( not -d $startPath ) {
        $HAS_ERROR = 1;
        die("ERROR: Start path:$startPath is not a directory.");
    }

    chdir($startPath);

    my $needMd5   = $self->{md5};
    my $needMTime = $self->{mtime};

    my @dirs = ("./");
    my ( $dir, $file, @statInfo );

    while ( $dir = pop(@dirs) ) {
        local *DH;
        if ( $dir eq "./" ) {
            if ( !opendir( DH, $dir ) ) {
                $HAS_ERROR = 1;
                die("ERROR: Open local path:$startPath failed:$!.");
                return;
            }
            $dir = "";
        }
        else {
            if ( !opendir( DH, $dir ) ) {
                $HAS_ERROR = 1;
                die("ERROR: Open local path:$dir failed:$!.");
                return;
            }
        }

        foreach ( readdir(DH) ) {
            if ( $_ eq "." || $_ eq ".." || $_ eq ".svn" || $_ eq ".git" ) {
                next;
            }

            $file = $dir . $_;
            if ( defined($xPath) and isExceptMatch( $sP, $eP, $file ) == 1 ) {
                next;
            }
            elsif ( !-l $file && -d $file ) {
                if ( @statInfo = stat($file) ) {
                    my @temp = ( $statInfo[9] . '_' . $statInfo[7], sprintf( "%04o", $statInfo[2] & 07777 ) );
                    $$outdirs{$file} = \@temp;
                }
                else {
                    $HAS_ERROR = 1;
                    die("ERROR: Stat local file:$file failed:$!.");
                }

                $file .= "/";
                push( @dirs, $file );
            }

            #排除更新用的tar文件
            elsif ( -f $file and $file !~ /^\.\d+\.\d+\.\d+\.\d+_(.*)_update_\d{8}\.tar$/ ) {
                if ( @statInfo = stat($file) ) {
                    my @temp;
                    if ( $needMd5 == 0 ) {
                        if ( $needMTime == 1 ) {
                            @temp = ( $statInfo[9] . '_' . $statInfo[7], sprintf( "%04o", $statInfo[2] & 07777 ) );
                        }
                        else {
                            @temp = ( $statInfo[7], sprintf( "%04o", $statInfo[2] & 07777 ) );
                        }
                    }
                    else {
                        @temp = ( $self->getFileMd5($file), sprintf( "%04o", $statInfo[2] & 07777 ) );
                    }
                    $$outfiles{$file} = \@temp;
                }
                else {
                    $HAS_ERROR = 1;
                    die("ERROR: Stat local file:$file failed:$!.");
                }
            }
        }
        closedir(DH);
    }

    return ( $outfiles, $outdirs );
}

#更新到发布目录
sub upgradeFiles {
    my ( $self, $sourcePath, $targetPath, $inExceptDirs, $noDelete, $noAttrs ) = @_;
    my ( $allSrcFiles, $allSrcDirs, $allTgtFiles, $allTgtDirs, $srcFile, $srcDir, $tgtFile, $tgtDir, $hasTar );
    my ( $allSrcFilesPrefix, $allSrcDirsPrefix );

    my $cmd           = '';
    my $cmdStr        = '';
    my $addDirCmdStr  = '';
    my $delDirCmdStr  = '';
    my $delFileCmdStr = '';
    my $bakCmdStr     = '';

    my $deployUtils = $self->{deployUtils};

    if ( $sourcePath eq '' ) {
        die('ERROR: Source directory not defined.');
    }
    elsif ( not -e $sourcePath ) {
        die("ERROR: Source directory:$sourcePath not exists.");
    }

    if ( $targetPath eq '' ) {
        die('ERROR: Destination directory not defined.');
    }
    elsif ( not -e $targetPath ) {
        die("ERROR: Destination directory:$targetPath not exists.");
    }

    my $version = $self->{version};
    $sourcePath = realpath($sourcePath);
    $targetPath = realpath($targetPath);

    my $journalFh;

    my $bakRootPath = "$targetPath.rollback/$version";
    my $nowtime     = $deployUtils->getTimeStr();
    my $bakDir      = "$bakRootPath/$nowtime";
    my $journalFh;

    if ( $self->{backup} == 1 ) {
        if ( not -e $bakRootPath ) {
            if ( not mkpath($bakRootPath) and not -e $bakRootPath ) {
                die("ERROR: Can not create backup directory:$bakRootPath\n");
            }
        }

        while ( mkpath($bakDir) == 0 ) {
            if ( -e $bakDir ) {
                sleep(1);
                $nowtime = $deployUtils->getTimeStr();
                $bakDir  = "$bakRootPath/$nowtime";
            }
            else {
                die("ERROR: Can not create backup directory:$bakDir:$!\n");
            }
        }

        if ( not -e $bakDir ) {
            die("ERROR: Can not create backup directory:$bakDir\n");
        }

        my $journalPath = "$bakDir/journal";

        $journalFh = IO::File->new(">>$journalPath");
        die("ERROR: Can not create rollback journal file:$journalPath:$!") if ( not defined($journalFh) );
        $journalFh->autoflush(1);

    }

    my $TMPDIR    = $self->{tmpDir};
    my $tmpDir    = File::Temp->newdir( DIR => $TMPDIR, CLEANUP => 1, SUFFIX => '.sync' );
    my $tarPath   = "$tmpDir/tar";
    my $shadowDir = "$bakDir/shadow";

    if ( not -e $tarPath ) {
        if ( not mkpath($tarPath) and not -e $tarPath ) {
            die("ERROR:  Can not create backup directory:$tarPath:$!\n");
        }
    }

    my $tarFileName = ".update\.tar";
    my $shFileName  = ".update\.sh";
    my $hasDiff     = 0;

    if ( -e "$tarPath/$tarFileName" ) {
        unlink("$tarPath/$tarFileName");    #删除tar文件，防止原来存在这样的文件
    }
    if ( -e "$tarPath/$shFileName" ) {
        unlink("$tarPath/$shFileName");     #删除脚本文件
    }

    if ( not -e $sourcePath ) {
        if ( $ENV{CMD_LINE} ) {
            my $restartCount = 1 + int( $ENV{RESTART_COUNT} );
            $ENV{RESTART_COUNT} = $restartCount;
            if ( $restartCount < 15 ) {
                print("WARN: Source path:$sourcePath not exists, retry...\n");
                sleep(2);
                exec( $ENV{CMD_LINE} );
            }
            else {
                die("ERROR: Source path:$sourcePath not exists or permission deny.");
            }
        }
        else {
            die("ERROR: Source path:$sourcePath not exists or permission deny.");
        }
    }

    print( "INFO: " . $deployUtils->getTimeForLog() . "begin get source file info for:$sourcePath...\n" );
    my ( $srcFiles, $srcDirs ) = $self->allLocalFiles( $sourcePath, $inExceptDirs );
    map { $$allSrcFiles{$_} = $$srcFiles{$_}; $$allSrcFilesPrefix{$_} = $sourcePath; } ( keys(%$srcFiles) );
    map { $$allSrcDirs{$_}  = $$srcDirs{$_};  $$allSrcDirsPrefix{$_}  = $sourcePath; } ( keys(%$srcDirs) );
    print( "INFO: " . $deployUtils->getTimeForLog() . "get source file info complete.\n" );

    #mkdir($targetPath) if ( not -e $targetPath );

    print( "INFO: " . $deployUtils->getTimeForLog() . "begin get target file info for:$targetPath...\n" );
    ( $allTgtFiles, $allTgtDirs ) = $self->allLocalFiles( $targetPath, $inExceptDirs );
    print( "INFO: " . $deployUtils->getTimeForLog() . "get target file info complete.\n" );

    chdir($sourcePath);

    #对比两个目录的文件和目录差异，并进行处理
    my ( @updatedFiles, @newFiles, @oldFiles, $chmodCmdStr );
    my ( $srcStat, $tgtStat, $srcMode, $tgtMode, $bakDirPath, $fPath, $fName );
    my $shadowPath;

    #查找出删除的文件，并生成删除的shell命令
    my ( @delFiles, @delDirs );

    if ( not defined($noDelete) or $noDelete eq 0 ) {
        chdir($targetPath);
        foreach $tgtFile ( keys(%$allTgtFiles) ) {
            if ( not exists( $$allSrcFiles{$tgtFile} ) ) {
                push( @delFiles, $tgtFile );
                $delFileCmdStr = "${delFileCmdStr}rm -f " . $deployUtils->escapeQuote($tgtFile) . "\n";
                $tgtStat       = $$allTgtFiles{$tgtFile};
                $tgtMode       = $$tgtStat[1];

                #print("预删除文件 $targetPath/$tgtFile\n");
                if ( $self->{backup} ) {
                    $shadowPath = "$shadowDir/$tgtFile";
                    $bakDirPath = dirname($shadowPath);

                    if ( print $journalFh ("f:d:$tgtMode:$tgtFile\n") ) {
                        if ( not -e $shadowPath ) {

                            #eval { mkpath( $bakDirPath, 0, 0775 ) if ( not -e $bakDirPath ); };
                            $self->mkShadowPath( $shadowDir, $targetPath, dirname($tgtFile) ) if ( not -e $bakDirPath );

                            if ( -f $tgtFile and -d $bakDirPath ) {
                                if ( not copy( $tgtFile, $shadowPath ) ) {
                                    die("ERROR: Backup failed, can not create backup directory:$shadowPath, $!.");
                                }
                                else {
                                    chmod( oct($tgtMode), $shadowPath );
                                }
                            }
                            elsif ( -l $tgtFile ) {
                                symlink( readlink($tgtFile), $shadowPath );
                            }
                        }
                    }
                    else {
                        die("ERROR: Backup failed, can not write to journal file:$!.");
                    }
                }
            }
        }

        #查找出删除的目录，并生成删除的shell命令
        chdir($targetPath);
        foreach $tgtDir ( keys(%$allTgtDirs) ) {
            if ( not exists( $$allSrcDirs{$tgtDir} ) ) {
                push( @delDirs, $tgtDir );
                $tgtStat      = $$allTgtDirs{$tgtDir};
                $tgtMode      = $$tgtStat[1];
                $delDirCmdStr = "${delDirCmdStr}if [ -e '$tgtDir' ]; then  rm -rf " . $deployUtils->escapeQuote($tgtDir) . "; fi\n";

                #print("预删除目录 $targetPath/$tgtDir\n");
                if ( $self->{backup} ) {
                    $shadowPath = "$shadowDir/$tgtDir";
                    $bakDirPath = dirname($shadowPath);

                    if ( print $journalFh ("d:d:$tgtMode:$tgtDir\n") ) {
                        if ( not -e $shadowPath ) {

                            #eval { mkpath( $bakDirPath, 0, 0775 ) if ( not -e $bakDirPath ); };
                            $self->mkShadowPath( $shadowDir, $targetPath, $tgtDir ) if ( not -e $shadowPath );

                            #if ( -d $tgtDir and -d $bakDirPath ) {
                            #    if ( not mkdir($shadowPath) ) {
                            #        die("ERROR: 备份失败，不能创建备份文件:$shadowPath.");
                            #    }
                            #    else {
                            #        chmod( oct($tgtMode), $shadowPath );
                            #    }
                            #}
                        }
                    }
                    else {
                        die("ERROR: Backup failed, can not write to journal file:$!.");
                    }
                }

            }
        }
    }

    print( "INFO: " . $deployUtils->getTimeForLog() . "find deleted files and dirs complete.\n" );

    #找出新增的目录
    my ( @newDirs, @modDirs );
    chdir($sourcePath);
    foreach $srcDir ( keys(%$allSrcDirs) ) {
        if ( $$allSrcDirsPrefix{$srcDir} eq $sourcePath ) {
            $srcStat = $$allSrcDirs{$srcDir};
            $srcMode = $$srcStat[1];

            #新增的目录
            if ( not exists( $$allTgtDirs{$srcDir} ) ) {
                push( @newDirs, $srcDir );

                if ( $self->{backup} ) {
                    if ( not print $journalFh ("d:a:$srcMode:$srcDir\n") ) {
                        die("ERROR: Backup failed, can not write to journal file:$!.");
                    }
                }

                #print("预创建目录 $targetPath/$srcDir\n");
                $addDirCmdStr = "${addDirCmdStr}if [ ! -e '$srcDir' ]; then mkdir -p '$srcDir'; fi\n";

                if ( not defined($noAttrs) or $noAttrs eq 0 ) {

                    #print("预更改目录$srcDir权限为", $$srcStat[1], "\n");
                    $chmodCmdStr = "chmod " . $$srcStat[1] . " " . $deployUtils->escapeQuote($srcDir) . "\n$chmodCmdStr";
                }
            }

            #修改的目录文件夹权限不一致
            elsif ( exists( $$allTgtDirs{$srcDir} ) ) {
                if ( not defined($noAttrs) or $noAttrs eq 0 ) {
                    $tgtStat = $$allTgtDirs{$srcDir};

                    #文件夹权限不一致，修改文件夹权限
                    #print("debug###:", join(',', @$srcStat), ":", join(',', @$tgtStat), "\n");
                    if ( $$srcStat[1] ne $$tgtStat[1] ) {
                        push( @modDirs, $srcDir );

                        if ( $self->{backup} ) {
                            $tgtMode = $$tgtStat[1];

                            $shadowPath = "$shadowDir/$srcDir";
                            if ( not print $journalFh ("d:m:$tgtMode:$srcDir\n") ) {
                                die("ERROR: Backup failed, can not write to journal file:$!.");
                            }
                        }

                        #print("预更改目录$srcDir权限为", $$srcStat[1], "\n");
                        $chmodCmdStr = "chmod " . $$srcStat[1] . " " . $deployUtils->escapeQuote($srcDir) . "\n$chmodCmdStr";
                    }
                }
            }
        }
    }

    print( "INFO: " . $deployUtils->getTimeForLog() . "find new dirs complete.\n" );

    #找出新增的文件和更改过的文件
    chdir($sourcePath);
    foreach $srcFile ( keys(%$allSrcFiles) ) {
        if ( $$allSrcFilesPrefix{$srcFile} eq $sourcePath ) {

            #新增的文件
            if ( not exists( $$allTgtFiles{$srcFile} ) ) {
                push( @updatedFiles, $srcFile );
                push( @newFiles,     $srcFile );

                $srcStat = $$allSrcDirs{$srcFile};
                $srcMode = $$srcStat[1];

                if ( $self->{backup} ) {
                    if ( not print $journalFh ("f:a:$srcMode:$srcFile\n") ) {
                        die("ERROR: Backup failed, can not write to journal file:$!.");
                    }
                }
            }

            #修改过的文件
            else {
                $srcStat = $$allSrcFiles{$srcFile};
                $tgtStat = $$allTgtFiles{$srcFile};
                $tgtMode = $$tgtStat[1];

                if ( $$srcStat[0] ne $$tgtStat[0] ) {
                    push( @updatedFiles, $srcFile );
                    push( @oldFiles,     $srcFile );

                    if ( $self->{backup} ) {
                        $shadowPath = "$shadowDir/$srcFile";
                        $bakDirPath = dirname($shadowPath);

                        if ( print $journalFh ("f:m:$tgtMode:$srcFile\n") ) {
                            if ( not -e $shadowPath ) {

                                #eval { mkpath( $bakDirPath, 0, 0775 ) if ( not -e $bakDirPath ); };
                                $self->mkShadowPath( $shadowDir, $targetPath, dirname($srcFile) );
                                if ( -d $bakDirPath ) {
                                    if ( not copy( "$targetPath/$srcFile", $shadowPath ) ) {
                                        die("ERROR: Backup failed, can not create backup directory:$shadowPath:$!.");
                                    }
                                    else {
                                        chmod( oct($tgtMode), $shadowPath );
                                    }
                                }
                            }
                        }
                        else {
                            die("ERROR: Backup failed, can not write to journal file:$!.");
                        }
                    }
                }

                if ( not defined($noAttrs) or $noAttrs eq 0 ) {
                    if ( $$srcStat[1] ne $tgtMode ) {

                        #print("预更改$srcFile权限为", $$srcStat[1], "\n");
                        $chmodCmdStr = "$chmodCmdStr\nchmod " . $$srcStat[1] . " " . $deployUtils->escapeQuote($srcFile);

                        if ( $self->{backup} ) {
                            if ( not print $journalFh ("f:m:$tgtMode:$srcFile\n") ) {
                                die("ERROR: Backup failed, can not write to journal file:$!.");
                            }
                        }
                    }
                }
            }
        }
    }

    print( "INFO: " . $deployUtils->getTimeForLog() . "find modified files complete.\n" );

    $cmdStr = "${delFileCmdStr}${addDirCmdStr}${delDirCmdStr}";

    #将所有需要更新的文件分批次打tar包
    my $countFiles = scalar(@updatedFiles);
    chdir($sourcePath);
    for ( my $i = 0 ; $i < $countFiles ; $i += 100 ) {
        $hasTar = 1;
        my $cmd = "tar rf $tarPath/$tarFileName";
        foreach my $file ( splice( @updatedFiles, 0, 100 ) ) {
            $cmd = $cmd . ' ' . $deployUtils->escapeQuote($file);
        }
        my $rc = $deployUtils->execmd($cmd);
        if ( $rc ne 0 ) {
            print("ERROR: Package and update files failed.\n");
            exit(-1);
        }
    }

    #更改tar文件权限
    if ( -e "$tarPath/$tarFileName" ) {
        $deployUtils->execmd("chmod 664 $tarPath/$tarFileName");
        print("Create $tarPath/$tarFileName complete.\n");
    }

    print( "INFO: " . $deployUtils->getTimeForLog() . "tar modified files and dirs complete.\n" );

    #如果有更新的文件则将文件拷贝到远程端
    if ( $hasTar == 1 ) {
        my $untarCmd = "umask 002;\ncd '$targetPath'\n#解开$tarFileName\n" . "tar xf '$tarPath/$tarFileName'";
        if ( $deployUtils->execmd($untarCmd) ne 0 ) {
            $HAS_ERROR = 1;
            die("ERROR: Execute update instruction failed.");
        }
    }

    if ( $chmodCmdStr ne '' ) {
        $cmdStr = "${cmdStr}$chmodCmdStr\n";
    }

    print( "INFO: " . $deployUtils->getTimeForLog() . "untar complete.\n" );

    chdir($sourcePath);

    #如果命令串非空，则执行
    if ( $cmdStr ne '' ) {
        my $fh = IO::File->new(">$tarPath/$shFileName");
        if ( defined($fh) ) {
            print $fh ($cmdStr);
            $fh->close();
            print("INFO: begin to execute the sync shell script...\n");
            $cmdStr = "umask 002;\ncd '$targetPath'\nsh '$tarPath/$shFileName'";
            if ( $deployUtils->execmd($cmdStr) ne 0 ) {
                $HAS_ERROR = 1;
                die("ERROR: Execute update instruction failed.");
            }
            else {
                print("INFO: execute the sync shell script complete.\n");
            }
        }
        else {
            $HAS_ERROR = 1;
            die("ERROR: Create synchronize script failed:$!.");
        }
    }

    print( "INFO: " . $deployUtils->getTimeForLog() . "execute update script complete.\n" );

    #将更新情况输出
    my ( $file, $diffCmd, $diffContent );
    print( "==============", $deployUtils->getTimeStr(), "===============\n" );
    foreach $file (@newDirs) {
        $hasDiff = 1;
        print("New Dir:$file\n");
    }
    foreach $file (@delDirs) {
        $hasDiff = 1;
        print("Del Dir:$file\n");
    }
    foreach $file (@modDirs) {
        $hasDiff = 1;
        print("Update Dir Permission:$file\n");
    }
    foreach $file (@delFiles) {
        $hasDiff = 1;
        print("Del File:$file\n");
    }
    foreach $file (@newFiles) {
        $hasDiff = 1;
        print("New File:$file\n");
    }
    foreach $file (@oldFiles) {
        $hasDiff = 1;
        print("Update File:$file\n");
    }

    print("Source and destination directory has no difference.\n") if ( $hasDiff == 0 );

    print("============================================\n");

    chdir($sourcePath);

    $journalFh->close() if ( defined($journalFh) );

    unlink("$tarPath/$tarFileName");
    unlink("$tarPath/$shFileName");
    rmtree($tarPath);
    rmtree($bakDir) if ( $self->{backup} eq 0 );

    #rmdir($bakRootPath);
}

sub rollback {
    my ( $self, $sourcePath, $targetPath ) = @_;

    my $version = $self->{version};
    $sourcePath = realpath($sourcePath);
    $targetPath = realpath($targetPath);

    my $bakDir = "$targetPath.rollback/$version";

    return 1 if ( not -e $bakDir );

    chdir($bakDir);
    my @allBakSubDirs = sort { $b cmp $a } bsd_glob("*");

    if ( scalar(@allBakSubDirs) > 0 ) {
        foreach my $timeStamp (@allBakSubDirs) {
            $self->oneRollback( $sourcePath, $targetPath, $timeStamp );
            print("INFO: Rollback to:$timeStamp\n");
        }

        rmtree($bakDir);
        print("SUCCESS: Mirror directory has been rollbacked, please redeploy it to the runtime envrionment.\n");
    }
    else {
        print("INFO: There is no any backup.\n");
    }

}

#根据$targetPath.rollback的记录，回退所有修改到$targetPath
sub oneRollback {
    my ( $self, $sourcePath, $targetPath, $timeStamp ) = @_;

    my $version = $self->{version};
    $sourcePath = realpath($sourcePath);
    $targetPath = realpath($targetPath);

    my $bakDir = "$targetPath.rollback/$version/$timeStamp";

    return 1 if ( not -e $bakDir );

    my $shadowDir   = "$bakDir/shadow";
    my $journalPath = "$bakDir/journal";

    my $journalFh = IO::File->new("<$journalPath");
    die("ERROR: can not create rollback journal file:$journalPath:$!") if ( not defined($journalFh) );

    my $rollbackError = 0;

    my $journalSize = -s $journalPath;
    my $content;
    $journalFh->read( $content, $journalSize );
    $journalFh->close();

    my @jLines = split( "\n", $content );

    my $line;
    my ( $fileType, $opType, $mode, $fileName, $shadowFile, $targetFile );

    for ( my $i = scalar(@jLines) ; $i >= 0 ; $i-- ) {

        $line = $jLines[$i];
        ( $fileType, $opType, $mode, $fileName ) = split( ':', $line );

        $shadowFile = "$shadowDir/$fileName";
        $targetFile = "$targetPath/$fileName";

        if ( $opType eq 'a' ) {
            if ( -e $targetFile ) {
                if ( not rmtree($targetFile) ) {
                    $rollbackError = 1;
                }
            }
        }
        elsif ( $opType eq 'm' and $fileType eq 'd' ) {
            if ( -e $targetFile ) {
                if ( not chmod( oct($mode), $targetFile ) ) {
                    $rollbackError = 1;
                }
            }
        }
    }

    if ( -d $shadowDir ) {
        my $deployUtils = $self->{deployUtils};
        if ( $deployUtils->execmd("cp -rp $shadowDir/. $targetPath/") ne 0 ) {
            $rollbackError = 1;
        }
    }

    if ( $rollbackError eq 1 ) {
        die("ERROR: Rollback to:$timeStamp failed.\n");
    }
    else {
        print("INFO: Rollback to:$timeStamp succeed\n");
    }

    chdir($sourcePath);

    if ( $rollbackError == 0 ) {
        rmtree($bakDir);
    }
    else {
        die("ERROR: Mirror directory rollback failed");
    }
}

1;

