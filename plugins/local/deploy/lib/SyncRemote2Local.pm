#!/usr/bin/perl
use strict;

package SyncRemote2Local;

use FindBin;
use IO::File;
use Expect;
use File::Glob qw(bsd_glob);
$Expect::Multiline_Matching = 0;
use Cwd 'realpath';
use Term::ANSIColor qw(uncolor);
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

use DeployUtils;
use TagentClient;

sub new {
    my ( $pkg, %args ) = @_;

    if ( not defined( $args{tmpDir} ) ) {
        $args{tmpDir} = '/tmp';
    }

    my $self = {
        port   => $args{port},
        tmpdir => $args{tmpDir},
        tmpDir => $args{tmpDir}
    };

    bless( $self, $pkg );

    return $self;
}

sub getDate {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime;
    my $nowdate = sprintf( '%d%02d%02d', $year + 1900, $mon + 1, $mday );

    return $nowdate;
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

#遍历计算文件时间过程
sub genFilesInfo {
    my ( $startPath, $xPath, $ticket ) = @_;

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

    my $tarPath      = realpath($startPath);
    my $fileListPath = "$tarPath/._update_$ticket.lst";
    my $LISTFH;
    if ( !open( $LISTFH, ">$fileListPath" ) ) {
        die("ERROR: Can not create file $fileListPath.");
    }

    mkdir($startPath) if ( not -e $startPath );
    if ( not -d $startPath ) {
        die("ERROR: destination path:$startPath not a directory.");
    }

    chdir($startPath);

    my @dirs = ("./");
    my ( $dir, $file, @statInfo );

    while ( $dir = pop(@dirs) ) {
        local *DH;
        if ( $dir eq "./" ) {
            if ( !opendir( DH, $dir ) ) {
                die("ERROR: Cannot opendir $startPath: $! $^E");
                return;
            }
            $dir = "";
        }
        else {
            if ( !opendir( DH, $dir ) ) {
                die("ERROR: Cannot opendir $dir: $! $^E");
                return;
            }
        }

        foreach ( readdir(DH) ) {
            if ( $_ eq "." || $_ eq ".." || $_ eq ".svn" || $_ eq ".git" || $_ =~ /^\._update_$ticket\./ ) {
                next;
            }

            $file = $dir . $_;
            if ( defined($xPath) and isExceptMatch( $sP, $eP, $file ) == 1 ) {
                next;
            }
            elsif ( !-l $file && -d _ ) {
                @statInfo = stat($file);
                print $LISTFH ( "d ", $file, " ", $statInfo[9], "_", $statInfo[7], " ", sprintf( "%04o", $statInfo[2] & 07777 ), "\n" );

                $file .= "/";
                push( @dirs, $file );
            }
            elsif ( -f $file ) {
                @statInfo = stat($file);
                print $LISTFH ( "f ", $file, " ", $statInfo[9], "_", $statInfo[7], " ", sprintf( "%04o", $statInfo[2] & 07777 ), "\n" );
            }
        }
        closedir(DH);
    }

    print("INFO: find local file info complete.\n");
}

#执行SSH命令过程
sub spawnSSHCmd {
    my ( $self, $inUser, $inPwd, $inIP, $inCmd, $isVerbose, $callback, @cbparams ) = @_;

    my $port  = $self->{'port'};
    my $spawn = new Expect;

    #$isVerbose = 1;

    #print("ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -p $port $inUser\@$inIP '$inCmd'");
    $spawn = Expect->spawn("ssh -x -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -p $port $inUser\@$inIP '$inCmd'");

    $spawn->raw_pty(1);
    $spawn->log_stdout($isVerbose);

    #use "\n" to match, no need to use max_accum, use max_accum will cause match lost
    #$spawn->max_accum(2048);
    my $hasSendPass = 0;

    my $lastLine = '';
    my $isClosed = 0;
    $spawn->expect(
        undef,
        [
            qr/password:\s*$/i => sub {
                if ( $hasSendPass == 0 ) {
                    $spawn->send("$inPwd\n");
                    $hasSendPass = 1;
                    $spawn->log_stdout($isVerbose);
                    exp_continue;
                }
                else {
                    $spawn->hard_close();
                    die("\nERROR: login failed, check username and password.\n");
                }
            }
        ],
        [
            "\n" => sub {
                my $firstLine = $spawn->before();
                if ( $firstLine =~ /^\s*$/ ) {
                    exp_continue;
                }
                else {
                    $lastLine = $firstLine;
                    if ( defined($callback) ) {
                        $callback->( $firstLine, @cbparams );
                    }

                    if ( $firstLine =~ /password:\s*$/ or $firstLine =~ /^Permission denied, please try again.\s*$/ ) {
                        $spawn->hard_close();
                        die("\nERROR: login failed, check username and password.\n");
                    }
                }
            }
        ],
        [
            eof => sub {
                $isClosed = 1;
                $spawn->soft_close();
            }
        ]
    );

    if ( $isClosed == 0 ) {
        my $isLogin = 0;
        $spawn->expect(
            undef,
            [
                "\n" => sub {
                    if ( $isLogin == 0 ) {
                        $isLogin = 1;
                        print( 'INFO: ' . DeployUtils->getTimeForLog() . "server $inUser\@$inIP:$port conntected.\n" );
                    }
                    $lastLine = $spawn->before();
                    $callback->( $lastLine, @cbparams ) if ( defined($callback) );
                    exp_continue;
                }
            ],
            [
                eof => sub {
                    $spawn->soft_close();
                }
            ]
        );
    }

    if ( $spawn->exitstatus() != 0 ) {
        if ( $lastLine ne '' ) {
            print("ERROR: $lastLine\n");
        }
        die("ERROR: SSH exec failed.");
    }
}

#拷贝文件到远程到远程
sub spawnSCP {
    my ( $self, $inUser, $inPwd, $inIP, $src, $dest, $isVerbose ) = @_;
    if ( $dest =~ /^[a-z]:/i ) {
        $dest =~ s{^([a-z]):}{/$1}g;
    }

    $isVerbose = 1;
    my $spawn = new Expect;
    print("INFO: scp $src $inUser\@$inIP:$dest \n");
    my $port = $self->{'port'};

    #print("DEBUG:scp -q -P$port $src $dest\n");
    #print("DEBUG: scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -P$port $src $dest \n");
    $spawn = Expect->spawn("scp -q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -P$port $src $dest ");
    $spawn->raw_pty(1);
    $spawn->log_stdout(0);

    #here can use max_accum, because scp only use in password input, juse expect in the beginning
    $spawn->max_accum(2048);

    my $hasSendPass = 0;

    my $ret = $spawn->expect(
        undef,
        [
            qr/password:\s*$/i => sub {
                if ( $hasSendPass == 0 ) {
                    $spawn->send("$inPwd\n");
                    $spawn->log_stdout($isVerbose);
                    $hasSendPass = 1;
                    exp_continue;
                }
                else {
                    $spawn->hard_close();
                    die("\nERROR: login failed, check username and password.\n");
                }
            }
        ],
        [
            eof => sub {
                my $lastLine = $spawn->before();
                $spawn->soft_close();
                if ( $spawn->exitstatus() != 0 and $lastLine =~ /lost connection/ ) {
                    die("ERROR: connect to server failed, $lastLine");
                }
            }
        ]
    );

    if ( $spawn->exitstatus() != 0 ) {
        die("ERROR: scp $src $inIP failed, check the log.");
    }
}

sub execRemoteCmd {
    my ( $self, $agentType, $inUser, $inPwd, $inIP, $inCmd, $isVerbose, $callback, @cbparams ) = @_;
    if ( $agentType eq 'ssh' ) {
        $self->spawnSSHCmd( $inUser, $inPwd, $inIP, $inCmd, $isVerbose, $callback, @cbparams );
    }
    elsif ( $agentType eq 'tagent' ) {
        my $port   = $self->{'port'};
        my $tagent = new TagentClient( $inIP, $port, $inPwd );
        my $ret    = $tagent->execCmd( $inUser, $inCmd, $isVerbose, undef, $callback, @cbparams );
        if ( $ret != 0 ) {
            die("ERROR: tagent execute remote command $inCmd failed.\n");
        }
    }
}

sub remoteCopy {
    my ( $self, $agentType, $inUser, $inPwd, $inIP, $inFiles, $inDir, $opType, $isVerbose ) = @_;

    if ( $agentType eq 'ssh' ) {
        if ( $opType eq 'upload' ) {
            my $scpSrc = "";
            foreach my $scpItem (@$inFiles) {
                $scpSrc = $scpSrc . " '$scpItem'";
            }

            $inDir = "$inUser\@$inIP:'$inDir'";
            $self->spawnSCP( $inUser, $inPwd, $inIP, $scpSrc, $inDir, $isVerbose );
        }
        else {
            foreach my $scpItem (@$inFiles) {
                $self->spawnSCP( $inUser, $inPwd, $inIP, "$inUser\@$inIP:'$scpItem'", $inDir, $isVerbose );
            }
        }
    }
    elsif ( $agentType eq 'tagent' ) {
        my $port   = $self->{'port'};
        my $tagent = new TagentClient( $inIP, $port, $inPwd );

        my $ret = 0;

        if ( $opType eq 'upload' ) {
            foreach my $srcItem (@$inFiles) {
                $ret = $tagent->upload( $inUser, $srcItem, $inDir, $isVerbose );
                if ( $ret != 0 ) {
                    last;
                }
            }
        }
        else {
            foreach my $srcItem (@$inFiles) {
                $ret = $tagent->download( $inUser, $srcItem, $inDir, $isVerbose );
                if ( $ret != 0 ) {
                    last;
                }
            }
        }

        if ( $ret != 0 ) {
            die("ERROR: tagent $opType failed.\n");
        }
    }
}

#更新到发布目录
sub upgradeFiles {
    my ( $self, $sourcePath, $sourceUser, $sourcePwd, $sourceIP, $targetPath, $inExceptDirs, $noDelete, $noAttrs, $followLinks, $agentType ) = @_;
    ($targetPath) = split( ',', $targetPath );

    my $perlSubs = q{
sub escapeQuote {
    my ($line) = @_;
    $line =~ s/([\\{\\}\\(\\)\\[\\]\\'\\"\\$\\s\\&])/\\\\$1/g;
    return $line;
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

sub allRemoteFiles {
    my ( $startPath, $listFile ) = @_;
    my ( %outfiles, %outdirs );
    
    my $listPath = "$startPath/$listFile";
    my $fh;
    if ( open($fh, "<$listPath") ){
        while($line = <$fh>){
            #print("DEBUG:getline:$line\n");
            if ( $line =~ /^f (.*)\s+(\d+_\d+)\s+(\d+)\s*$/ ) {
                my @temp = ( $2, $3 );
                $outfiles{$1} = \@temp;
            }
            elsif ( $line =~ /^d (.*)\s+(\d+_\d+)\s+(\d+)\s*$/ ) {
                my @temp = ( $2, $3 );
                $outdirs{$1} = \@temp;
            }
        }
        close($fh);
    }
    
    unlink($listPath);
    return (\%outfiles, \%outdirs);
}


#遍历本地文件时间过程
sub allLocalFiles {
    my ( $startPath, $xPath, $ticket ) = @_;

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

    if ( not -d $startPath ) {
        die("ERROR: Start path:$startPath is not a directory.");
    }

    chdir($startPath);

    my @dirs = ("./");
    my ( $dir, $file, @statInfo );

    while ( $dir = pop(@dirs) ) {
        local *DH;
        if ( $dir eq "./" ) {
            if ( !opendir( DH, $dir ) ) {
                die("ERROR: Local path:$startPath not exists or permission deny.");
                return;
            }
            $dir = "";
        }
        else {
            if ( !opendir( DH, $dir ) ) {
                die("ERROR: Local path:$dir not exists or permission deny.");
                return;
            }
        }

        foreach ( readdir(DH) ) {
            if ( $_ eq "." || $_ eq ".." || $_ eq ".svn" || $_ eq ".git" || $_ =~ /^\._update_$ticket\./ ) {
                next;
            }

            $file = $dir . $_;
            if ( defined($xPath) and isExceptMatch( $sP, $eP, $file ) == 1 ) {
                next;
            }
            elsif ( !-l $file && -d _ ) {
                if ( @statInfo = stat($file) ) {
                    my @temp = ( $statInfo[9] . '_' . $statInfo[7], sprintf( "%04o", $statInfo[2] & 07777 ) );
                    $$outdirs{$file} = \@temp;
                }
                else {
                    die("ERROR: Local file:$file permission deny.");
                }

                $file .= "/";
                push( @dirs, $file );
            }

            #排除更新用的tar文件
            elsif ( -f $file ) {
                if ( @statInfo = stat($file) ) {
                    my @temp = ( $statInfo[9] . '_' . $statInfo[7], sprintf( "%04o", $statInfo[2] & 07777 ) );
                    $$outfiles{$file} = \@temp;
                }
                else {
                    die("ERROR: Local file:$file permission deny.");
                }
            }
        }
        closedir(DH);
    }

    return ( $outfiles, $outdirs );
}

#更新到发布目录
sub genUpdateTar {
    my ( $sourcePath, $inExceptDirs, $ticket, $noDelete, $noAttrs, $followLinks ) = @_;
    my ( $allSrcFiles, $allSrcDirs, $allTgtFiles, $allTgtDirs, $srcFile, $srcDir, $tgtFile, $tgtDir, $hasTar );
    my ( $allSrcFilesPrefix, $allSrcDirsPrefix );
    my ( $srcStat, $tgtStat, $srcMode, $tgtMode );
    my $cmdStr  = '';
    my $chmodCmdStr = '';

    my $followLinksOpt = '';
    if ( defined($followLinks) ){
        $followLinksOpt = 'h';
    }

    if ( $sourcePath eq '' ) {
        die('ERROR: Source directory is empty.');
    }

    use Cwd qw(realpath);
    my $tarPath     = realpath( $sourcePath );
    my $tarFileName = "._update_$ticket.tar";
    my $shFileName = "._update_$ticket.sh";
    my $listFileName = "._update_$ticket.lst";
    

    if ( -e "$tarPath/$tarFileName" ) {
        unlink("$tarPath/$tarFileName");    #删除tar文件，防止原来存在这样的文件
    }
    if ( -e "$tarPath/$shFileName" ) {
        unlink("$tarPath/$shFileName");     #删除脚本文件
    }

    my $emptyTar;
    open($emptyTar, ">$tarPath/$tarFileName");
    if ( defined($emptyTar) ){
        for( my $i=0; $i<10; $i++ ){
            print $emptyTar ("\0"x1024);
        }
        close($emptyTar);
    }

    $sourcePath = realpath($sourcePath);
    ( $allTgtFiles, $allTgtDirs ) = allRemoteFiles( $sourcePath, $listFileName, $ticket );
    
    if ( not -e $sourcePath ) {
        die("ERROR: Source path:$sourcePath not exists or permission deny.");
    }
    print("INFO: begin to find file info for $sourcePath...\n");
    my ( $srcFiles, $srcDirs ) = allLocalFiles( $sourcePath, $inExceptDirs, $ticket );
    print("INFO: find file info for $sourcePath complete.\n");

    map { $$allSrcFiles{$_} = $$srcFiles{$_}; $$allSrcFilesPrefix{$_} = $sourcePath; } ( keys(%$srcFiles) );
    map { $$allSrcDirs{$_}  = $$srcDirs{$_};  $$allSrcDirsPrefix{$_}  = $sourcePath; } ( keys(%$srcDirs) );


   my $needCreateTar = 1;
    my ( @updatedFiles, @newFiles, @oldFiles, @delFiles, @newDirs, @modDirs, @delDirs );
 
        chdir($sourcePath);

        #找出新增的文件和更改过的文件
        foreach $srcFile ( keys(%$allSrcFiles) ) {
            if ( $$allSrcFilesPrefix{$srcFile} eq $sourcePath ) {
                if ( not exists( $$allTgtFiles{$srcFile} ) ) {
                    push( @updatedFiles, $srcFile );
                    push( @newFiles,     $srcFile );
                }
                else {
                    $srcStat = $$allSrcFiles{$srcFile};
                    $tgtStat = $$allTgtFiles{$srcFile};

                    if ( $$srcStat[0] ne $$tgtStat[0] ) {
                        push( @updatedFiles, $srcFile );
                        push( @oldFiles,     $srcFile );
                    }
                    if ( not defined($noAttrs) or $noAttrs eq 0 ){
                        if ( $$srcStat[1] ne $$tgtStat[1] ) {
                            #print("预更改$srcFile权限为", $$srcStat[1], "\n");
                            $chmodCmdStr = "chmod " . $$srcStat[1] . " " . escapeQuote($srcFile) . " || exit 1\n$chmodCmdStr";
                        }
                    }
                }
            }
        }

        #将所有需要更新的文件分批次打tar包
        my $countFiles = scalar(@updatedFiles);
            for ( my $i = 0 ; $i < $countFiles ; $i += 100 ) {
            $hasTar = 1;
            my $cmd = "tar r${followLinksOpt}f $tarPath/$tarFileName";
            if ( $needCreateTar == 1 )
            {
                $cmd = "tar c${followLinksOpt}f $tarPath/$tarFileName";
                $needCreateTar = 0;
            }

            foreach my $file ( splice( @updatedFiles, 0, 100 ) ) {
                $cmd = $cmd . ' ' . escapeQuote($file);
            }
            my $rc = system($cmd);
            if ( $rc ne 0 ) {
                print("ERROR: package and update files failed.\n$cmd\n");
                exit(-1);
            }
        }

        #找出新增的目录
        foreach $srcDir ( keys(%$allSrcDirs) ) {
            if ( $$allSrcDirsPrefix{$srcDir} eq $sourcePath ) {
                $srcStat = $$allSrcDirs{$srcDir};
                if ( not exists( $$allTgtDirs{$srcDir} ) ) {

                    push( @newDirs, $srcDir );
                    $cmdStr = "${cmdStr}if [ ! -e '$srcDir' ]; then mkdir -p '$srcDir'; fi\n";

                    if ( not defined($noAttrs) or $noAttrs eq 0 ){
                        #print("预更改目录$srcDir权限为", $$srcStat[1], "\n");
                        $chmodCmdStr = "chmod " . $$srcStat[1] . " " . escapeQuote($srcDir) . " || exit 1\n$chmodCmdStr";
                    }
                }
                else {
                    $tgtStat = $$allTgtDirs{$srcDir};
                    if ( not defined($noAttrs) or $noAttrs eq 0 ){
                        if ( $$srcStat[1] ne $$tgtStat[1] ) {
                            push( @modDirs, $srcDir );
                            #print("预更改目录$srcDir权限为", $$srcStat[1], "\n");
                            $chmodCmdStr = "chmod " . $$srcStat[1] . " " . escapeQuote($srcDir) . " || exit 1\n$chmodCmdStr";
                        }
                    }
                }
            }
        }


    #更改tar文件权限
    if ( -e "$tarPath/$tarFileName" ) {
        system("chmod 660 $tarPath/$tarFileName");
        print("Create $tarPath/$tarFileName complete.\n");
    }

    if ( not defined( $noDelete ) or $noDelete eq 0 ){
        #查找出删除的文件，并生成删除的shell命令
        foreach $tgtFile ( keys(%$allTgtFiles) ) {
            if ( not exists( $$allSrcFiles{$tgtFile} ) ) {
                $cmdStr = "${cmdStr}if [ -e " . escapeQuote($tgtFile) . " ]; then rm -f " . escapeQuote($tgtFile) . " || exit 1; fi\n";
                push( @delFiles, $tgtFile );
            }
        }
        foreach $tgtDir ( keys(%$allTgtDirs) ) {
            if ( not exists( $$allSrcDirs{$tgtDir} ) ) {
                $cmdStr = "${cmdStr}if [ -e " . escapeQuote($tgtDir) . " ]; then  rm -rf " . escapeQuote($tgtDir) . " || exit 1; fi\n";
                push( @delDirs, $tgtDir );
            }
        }
    }

    #如果有更新的文件则将文件拷贝到远程端
    if ( $hasTar == 1 ) {
        $cmdStr = "tar x${followLinksOpt}f $tarFileName || exit 1\nrm -f $tarFileName || exit 1\n" . $cmdStr;
    }

    if ( $chmodCmdStr ne '' ) {
        $cmdStr = "$cmdStr\n$chmodCmdStr";
    }

    #如果远程命令串非空，则连接到远程机器执行
    $cmdStr = "umask 000\nunalias tar >/dev/null 2>\&1\n$cmdStr";

    my $shFH;
    if ( open($shFH, ">$tarPath/$shFileName") ){
        print $shFH ($cmdStr);
        close($shFH);
    }
    else {
        die("ERROR: Create update script file:$tarPath/$shFileName failed");
    }

    #将更新情况输出
    my $hasDiff = 0;
    my $file;
    print( "============================================\n" );
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
}
};

    my $hasError   = 0;
    my $checkError = sub {
        my ( $line, $hasError ) = @_;

        #print("DEBUG:getline:$line\n");
        if ( $line =~ /Permission\s+denied/i ) {
            $$hasError = 1;
        }
        elsif ( $line =~ /^ERROR:/ ) {
            $$hasError = 1;
        }
    };

    mkdir($targetPath) if ( not -e $targetPath );
    my $ticket = getDate();

    END {
        local $?;
        my $file;
        foreach $file ( bsd_glob("$targetPath/._update_$ticket*") ) {
            unlink($file);
        }
    }

    my $endSub = q{
       END {
           my $exitCode=$?;
           local $?;
           if($exitCode != 0){
               my $file;
               foreach $file (bsd_glob("$sourcePath/._update_$ticket*")){
                   unlink($file);
               }
           }
      };
    };
    $endSub =~ s/\$sourcePath/$sourcePath/;

    my $perlCmd = "use File::Glob qw(bsd_glob); my \$ticket='$ticket';" . $endSub . $perlSubs . qq{\ngenUpdateTar("$sourcePath","$inExceptDirs", "$ticket", $noDelete, $noAttrs, $followLinks);};
    my $cmdFile = new IO::File(">$targetPath/._update_$ticket.pl");
    print $cmdFile ($perlCmd);
    $cmdFile->close();

    genFilesInfo( $targetPath, $inExceptDirs, $ticket );

    $self->remoteCopy( $agentType, $sourceUser, $sourcePwd, $sourceIP, [ "$targetPath/._update_$ticket.lst", "$targetPath/._update_$ticket.pl" ], $sourcePath, 'upload', 1 );

    $self->execRemoteCmd( $agentType, $sourceUser, $sourcePwd, $sourceIP, "unalias tar >/dev/null 2>\&1; perl '$sourcePath/._update_$ticket.pl'", 1, $checkError, \$hasError );

    $self->remoteCopy( $agentType, $sourceUser, $sourcePwd, $sourceIP, [ "$sourcePath/._update_$ticket.tar", "$sourcePath/._update_$ticket.sh" ], $targetPath, 'download', 1 );

    my $delCmd = "rm -f $sourcePath/._update_$ticket.*";
    $self->execRemoteCmd( $agentType, $sourceUser, $sourcePwd, $sourceIP, $delCmd, 0 );

    my $shFileName = "._update_$ticket.sh";
    if ( -e "$targetPath/$shFileName" ) {
        my $execCmd = "cd '$targetPath'\nsh $shFileName\nrm $shFileName";
        my $rc      = DeployUtils->execmd($execCmd);

        die("ERROR:Exeucte sync failed.\n") if ( $rc ne 0 );
    }
}

1;

