#!/usr/bin/perl
use strict;

package SyncLocal2Remote;
use FindBin;
use IO::File;
use Expect;
use Encode;
use Encode::Guess;
use File::Temp;
use File::Copy;
use File::Glob qw(bsd_glob);

use DeployUtils;
use TagentClient;
$Expect::Multiline_Matching = 0;
use Cwd 'realpath';

sub new {
    my ( $pkg, %args ) = @_;

    if ( not defined( $args{tmpDir} ) ) {
        $args{tmpDir} = '/tmp';
    }

    my $self = {
        port        => $args{port},
        deleteOnly  => $args{deleteOnly},
        tmpDir      => $args{tmpDir},
        deployUtils => DeployUtils->new()
    };

    if ( not defined( $self->{deleteOnly} ) ) {
        $self->{deleteOnly} = 0;
    }

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

#遍历计算远程文件时间过程
sub allRemoteFiles {
    my ( $self, $ostype, $inUser, $inPwd, $inIP, $instanceName, $inPath, $xPath, $agentType, $followLinks ) = @_;
    my ( $line, @lines );
    my $prefixLen = length($inPath);
    my ( $filePath, $fileTime, $fileMode );
    my ( %outfiles, %outdirs );

    my $deployUtils = $self->{deployUtils};

    my $getFileInfoLine = sub {
        my ( $line, $outfiles, $outdirs ) = @_;

        #print("DEBUG:getline:$line\n");
        #if ( $line =~ /Permission\s+denied/i ) {
        #    die("ERROR: Remote file permission deny.");
        #}

        if ( $line =~ /^f (.*)\s+(\d+_\d+)\s+(\d+)\s*$/ ) {

            #$filePath = $1; $fileTime = $2; $fileMode = $3;
            #print("DEBUG:getfile:$1\n");
            my @temp = ( $2, $3 );
            $outfiles->{$1} = \@temp;
        }
        elsif ( $line =~ /^d (.*)\s+(\d+_\d+)\s+(\d+)\s*$/ ) {

            #$filePath = $1; $fileTime = $2; $fileMode = $3;
            my @temp = ( $2, $3 );
            $outdirs->{$1} = \@temp;
        }
        elsif ( $line =~ /^ERROR:/ ) {
            print( $line, "\n" );
        }
    };

    print("INFO: Begin sync, it will take a few minutes...\n");

    my $calcPerlSub = q{
    sub isExceptMatch {
        my ($sPrefixs, $ePrefixs, $path) = @_;
    
        my ($sPrefix, $ePrefix);
    
        foreach $sPrefix (@$sPrefixs){
            if(substr($path, 0, length($sPrefix)) eq $sPrefix){
                return 1;
            }
        }
    
        foreach $ePrefix (@$ePrefixs){
            if(substr($path, -length($ePrefix)) eq $ePrefix){
                return 1;
            }
        }
    
        return 0;
    }

    sub searchrecusion {
        my ( $startPath, $xPath ) = @_;
        my $hasError = 0; 
        my (@sPrefixs, @ePrefixs);
        if ( defined($xPath) ) {
            my @tmpDirs = split( /\s*,\s*/, $xPath );
            foreach my $tmpdir (@tmpDirs) {
                if($tmpdir =~ /\$$/){
                    $tmpdir =~ s/\$$//;
                    push(@ePrefixs, $tmpdir);
                }
                else{
                    push(@sPrefixs, $tmpdir);
                }
            }
        }
        my $sP = \@sPrefixs;
        my $eP = \@ePrefixs;
    
        mkdir($startPath) if ( not -e $startPath );
        if ( not -d $startPath ){
            print("ERROR: Destination path:$startPath not a directory.");
            return 2;
        }
        chdir($startPath);
    
        my @dirs = ("./");
        my ( $dir, $file, @statInfo );
    
        while ( $dir = pop(@dirs) ) {
            local *DH;
            if ( $dir eq "./" ) {
                if ( !opendir( DH, $dir ) ) {
                    print("ERROR: Cannot opendir $startPath: $^E");
                    return 2;
                }
                $dir = "";
            }
            else {
                if ( !opendir( DH, $dir ) ) {
                    print("ERROR: Cannot opendir $dir: $^E");
                    $hasError = 1;
                    next;
                }
            }
    
            foreach ( readdir(DH) ) {
                if ( $_ eq "." || $_ eq ".." || $_ eq ".svn" || $_ eq ".git") {
                    next;
                }
    
                $file = $dir . $_;
                if ( defined($xPath) and isExceptMatch($sP, $eP, $file) == 1 ) {
                    next;
                }
                elsif ( !-l $file && -d $file ) {
                    @statInfo = stat($file);
                    print( "d ", $file, " ", $statInfo[9], "_", $statInfo[7], " ", sprintf( "%04o", $statInfo[2] & 07777 ), "\n" );
    
                    $file .= "/";
                    push( @dirs, $file );
                }
                elsif ( -f $file ) {
                    @statInfo = stat($file);
                    print( "f ", $file, " ", $statInfo[9], "_", $statInfo[7], " ", sprintf( "%04o", $statInfo[2] & 07777 ), "\n" );
                }
            }
            closedir(DH);
        }
        return $hasError;
    }
  };

    if ( defined($xPath) ) {
        $xPath =~ s/\$$/\\\$/;
        $xPath =~ s/\$,/\\\$,/g;
    }

    my $cmd = $calcPerlSub . qq{mkdir("$inPath") if (not -e "$inPath"); exit(searchrecusion("$inPath","$xPath"));};
    if ( $ostype eq 'windows' ) {
        my $nowdate    = $deployUtils->getDate();
        my $pmFileName = ".$inIP\_$instanceName\_update_$nowdate.pm";
        my $fh         = new IO::File("> /tmp/$pmFileName");
        die("ERROR: Create update script file:$pmFileName failed.\n") if ( not defined($fh) );
        $cmd = "#!/usr/bin/perl
      use FindBin;\nuse strict;\nuse warnings;\n" . $cmd;
        print $fh ($cmd);
        $fh->close();
        $self->remoteCopy( $agentType, $inUser, $inPwd, $inIP, "/tmp/$pmFileName", "$inPath/..", 1, 1 );
        unlink("/tmp/$pmFileName");

        #$cmd = "cmd /c perl $inPath/../$pmFileName";
        $cmd = "cmd /c perl \"$inPath/../$pmFileName\"";
        $self->execRemoteCmdWindows( $agentType, $inUser, $inPwd, $inIP, $cmd, 0, $getFileInfoLine, \%outfiles, \%outdirs );
        my $temp_pmPath = "$inPath/../$pmFileName";

        #$temp_pmPath =~ s/\//\\\\\\\\/g;
        $temp_pmPath =~ s/\//\\/g;
        $self->execRemoteCmdWindows( $agentType, $inUser, $inPwd, $inIP, "cmd /c del \"$temp_pmPath\"" );
    }
    else {

        #$cmd =~ s/\\/\\\\/igs;    #将反斜杠转义处理
        #$cmd =~ s/"/\\"/igs;      #将双引号转义处理
        #$cmd =~ s/\$/\\\$/igs;    #将$号转义处理
        #$cmd = qq{perl -e '\\''$cmd'\\''};
        $cmd =~ s/\s+/ /g;
        $self->execRemoteCmd( $agentType, $inUser, $inPwd, $inIP, $cmd, 0, $getFileInfoLine, \%outfiles, \%outdirs );
    }

    #for ( sort keys %outfiles ) {
    #    my $key = $_;
    #    for ( @{ $outfiles{$key} } ) {
    #        print BLUE "$key  ==>  $_\n";
    #    }
    #}

    return ( \%outfiles, \%outdirs );
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
                    die("ERROR: Local file:$file permission deny.");
                }

                $file .= "/";
                push( @dirs, $file );
            }

            #排除更新用的tar文件
            elsif ( -f $file and $file !~ /^\.\d+\.\d+\.\d+\.\d+_(.*)_update_\d{8}\.tar$/ ) {
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
                    die("\nERROR: Login failed, check username and password.\n");
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
                        die("\nERROR: Login failed, check username and password.\n");
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

    my $deployUtils = $self->{deployUtils};
    if ( $isClosed == 0 ) {
        my $isLogin = 0;
        $spawn->expect(
            undef,
            [
                "\n" => sub {
                    if ( $isLogin == 0 ) {
                        $isLogin = 1;
                        print("INFO: Server $inUser\@$inIP:$port conntected.\n");
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
    my ( $self, $inUser, $inPwd, $inIP, $inFiles, $inDir, $isVerbose ) = @_;
    if ( $inDir =~ /^[a-z]:/i ) {
        $inDir =~ s{^([a-z]):}{/$1}g;
    }
    my $spawn = new Expect;
    print("scp $inFiles $inUser\@$inIP:$inDir \n");
    my $port = $self->{'port'};
    $spawn = Expect->spawn("scp -q -P$port -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $inFiles $inUser\@$inIP:$inDir ");
    $spawn->raw_pty(1);
    $spawn->log_stdout(0);
    $spawn->max_accum(1024);

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
                    die("\nERROR: Login failed, check username and password.\n");
                }
            }
        ],
        [
            eof => sub {
                my $lastLine = $spawn->before();
                $spawn->soft_close();
                if ( $spawn->exitstatus() != 0 and $lastLine =~ /lost connection/ ) {
                    die("ERROR: Connect to server failed, $lastLine");
                }
            }
        ]
    );

    if ( $spawn->exitstatus() != 0 ) {
        die("ERROR: Scp $inFiles $inIP failed, check the log.");
    }
}

sub execRemoteCmd {
    my ( $self, $agentType, $inUser, $inPwd, $inIP, $inCmd, $isVerbose, $callback, @cbparams ) = @_;
    if ( $agentType eq 'tagent' ) {
        my $port   = $self->{'port'};
        my $tagent = new TagentClient( $inIP, $port, $inPwd );
        if ( defined($callback) ) {
            $inCmd = qq{perl -e '$inCmd'};
            $inCmd =~ s/\s+/ /g;
        }
        my $ret = $tagent->execCmd( $inUser, $inCmd, $isVerbose, undef, $callback, @cbparams );
        if ( $ret != 0 ) {
            die("ERROR: Tagent execute remote command failed.\n");
        }
    }
    else {
        if ( defined($callback) ) {
            $inCmd = qq{perl -e '\\''$inCmd'\\''};
        }
        $self->spawnSSHCmd( $inUser, $inPwd, $inIP, $inCmd, $isVerbose, $callback, @cbparams );
    }
}

sub execRemoteCmdWindows {
    my ( $self, $agentType, $inUser, $inPwd, $inIP, $inCmd, $isVerbose, $callback, @cbparams ) = @_;
    if ( $agentType eq 'tagent' ) {
        my $port   = $self->{'port'};
        my $tagent = new TagentClient( $inIP, $port, $inPwd );
        my $ret    = $tagent->execCmd( $inUser, $inCmd, $isVerbose, undef, $callback, @cbparams );
        if ( $ret != 0 ) {
            die("ERROR: Tagent execute remote command failed.\n");
        }
    }
    else {
        $self->spawnSSHCmd( $inUser, $inPwd, $inIP, $inCmd, $isVerbose, $callback, @cbparams );
    }
}

sub convertFileEncoding {
    my ( $self, $srcFile, $toCharset ) = @_;

    my $toCharset            = lc($toCharset);
    my $possibleEncodingConf = 'GBK,UTF-8';
    my @possibleEncodings    = ( 'GBK', 'UTF-8' );
    if ( defined($possibleEncodingConf) and $possibleEncodingConf ne '' ) {
        @possibleEncodings = split( /\s*,\s*/, $possibleEncodingConf );
    }

    my $srcFh = IO::File->new("<$srcFile");
    if ( defined($srcFh) ) {
        my $tmpdir = $self->{tmpDir};
        my $tmp    = File::Temp->new( DIR => $tmpdir, UNLINK => 1, SUFFIX => '.syncfile.cmd' );
        if ( defined($tmp) ) {
            my $line;
            while ( $line = $srcFh->getline() ) {
                my $enc = guess_encoding( $line, @possibleEncodings );
                my $charSet;
                if ( ref($enc) and $enc->mime_name ne 'US-ASCII' ) {
                    $charSet = lc( $enc->mime_name );
                }
                if ( not defined($charSet) ) {
                    $charSet = 'utf-8';
                }

                if ( defined($charSet) and $charSet ne $toCharset ) {
                    $line = Encode::encode( $toCharset, Encode::decode( $charSet, $line ) );
                }
                print $tmp ($line);
            }
            $srcFh->close();
            $tmp->close();
            File::Copy::cp( $tmp->filename, $srcFile );
        }
        else {
            die("ERROR: Convert command file to charset:$toCharset failed, cause:create tmp file in $tmpdir failed $!.\n");
        }
    }
    else {
        die("ERROR: Can not open file $srcFile convert charset to $toCharset failed.\n");
    }

    return;
}

sub remoteCopy {
    my ( $self, $agentType, $inUser, $inPwd, $inIP, $inFiles, $inDir, $isVerbose, $convertCharset ) = @_;
    if ( $agentType eq 'ssh' ) {
        $self->spawnSCP( $inUser, $inPwd, $inIP, $inFiles, $inDir, $isVerbose );
    }
    elsif ( $agentType eq 'tagent' ) {
        my $port   = $self->{'port'};
        my $tagent = new TagentClient( $inIP, $port, $inPwd );
        my $ret    = $tagent->echo('x');
        if ( $ret == 0 ) {
            if ( defined($convertCharset) and $convertCharset == 1 ) {
                my $agentCharset = lc( $tagent->{agentCharset} );
                if ( $agentCharset eq 'utf8' ) {
                    $agentCharset = 'utf-8';
                }

                $self->convertFileEncoding( $inFiles, $agentCharset );
            }
            $ret = $tagent->upload( $inUser, $inFiles, $inDir, $isVerbose );
        }

        if ( $ret != 0 ) {
            die("ERROR: Tagent upload failed.\n");
        }
    }
}

#更新到发布目录
sub upgradeFiles {
    my ( $self,              $ostype,     $sourcePaths, $targetUser, $targetPwd, $targetIP, $instanceName, $targetPath, $inExceptDirs, $noDelete, $noAttrs, $followLinks, $addExeModForNewFile, $agentType ) = @_;
    my ( $allSrcFiles,       $allSrcDirs, $allTgtFiles, $allTgtDirs, $srcFile,   $srcDir,   $tgtFile, $tgtDir, $hasTar );
    my ( $allSrcFilesPrefix, $allSrcDirsPrefix );
    my ( $srcStat,           $tgtStat, $srcMode, $tgtMode );

    my $deployUtils = $self->{deployUtils};
    my $nowdate     = $deployUtils->getDate();

    my $cmdStr            = '';
    my $cmdStr_forwindows = '';    #用来调整语句顺序，把删除语句写到创建语句之前，这样可以回避windows特有的文件名不分大小写的问题
    my $chmodCmdStr       = '';

    my $followLinksOpt = '';
    if ( defined($followLinks) ) {
        $followLinksOpt = 'h';
    }

    if ( $sourcePaths eq '' ) {
        die('ERROR: Source directory is empty.');
    }

    if ( $targetPath eq '' ) {
        die('ERROR: Destination directory not defined.');
    }

    if ( defined $ostype and $ostype eq 'windows' ) {
        $targetPath =~ s/\\/\//ig;
    }
    else {
        $ostype = 'unix';
    }

    if ( not defined($instanceName) ) {
        $instanceName = '';
    }

    my @allSrcPath = split( ',', $sourcePaths );

    my $tarFileName = ".$targetIP\_$instanceName\_update_$nowdate.tar";
    my $shFileName;
    if ( $ostype eq 'windows' ) {
        $shFileName = ".$targetIP\_$instanceName\_update_$nowdate.bat";
    }
    else {
        $shFileName = ".$targetIP\_$instanceName\_update_$nowdate.sh";
    }

    END {
        local $?;
        my $file;
        foreach $file ( bsd_glob(".$targetIP\_$instanceName\_update_$nowdate.*") ) {
            unlink($file);
        }
    }

    my $TMPDIR  = $self->{tmpDir};
    my $tarPath = File::Temp->newdir( DIR => $TMPDIR, CLEANUP => 1, SUFFIX => '.sync' );

    #my $tarPath     = realpath( $allSrcPath[0] . '/..' );
    if ( -e "$tarPath/$tarFileName" ) {
        unlink("$tarPath/$tarFileName");    #删除tar文件，防止原来存在这样的文件
    }
    if ( -e "$tarPath/$shFileName" ) {
        unlink("$tarPath/$shFileName");     #删除脚本文件
    }

    print("INFO: Begin get remote files info...\n");
    ( $allTgtFiles, $allTgtDirs ) = $self->allRemoteFiles( $ostype, $targetUser, $targetPwd, $targetIP, $instanceName, $targetPath, $inExceptDirs, $agentType, $followLinks );
    print("INFO: Get remote files info complete.\n");

    #print BLUE "\n--------------------------------------------------- $allTgtFiles -------------------------------------------------\n";
    #for ( sort keys %$allTgtFiles ) {
    #    my $key = $_;
    #    for ( @{ $allTgtFiles->{$key} } ) {
    #        #print BLUE "$key  ==>  $_\n";
    #    }
    #}

    #print BLUE "\n--------------------------------------------------- $allTgtDirs -------------------------------------------------\n";
    #for ( sort keys %$allTgtDirs ) {
    #    my $key = $_;
    #    for ( @{ $allTgtDirs->{$key} } ) {
    #        #print BLUE "$key  ==>  $_\n";
    #    }
    #}

    my $sourcePath;
    foreach $sourcePath (@allSrcPath) {
        $sourcePath = realpath($sourcePath);

        if ( not -e $sourcePath ) {
            die("ERROR: Source path:$sourcePath not exists or permission deny.");
        }
        print("INFO: Begin to find file info for $sourcePath...\n");
        my ( $srcFiles, $srcDirs ) = $self->allLocalFiles( $sourcePath, $inExceptDirs );
        print("INFO: Find file info for $sourcePath complete.\n");

        #print GREEN "\n--------------------------------------------------- $allTgtFiles -------------------------------------------------\n";
        #for ( sort keys %$srcFiles ) {
        #    my $key = $_;
        #    for ( @{ $srcFiles->{$key} } ) {
        #        #print GREEN "$key  ==>  $_\n";
        #    }
        #}

        #print GREEN "\n--------------------------------------------------- $allTgtDirs -------------------------------------------------\n";
        #for ( sort keys %$srcDirs ) {
        #    my $key = $_;
        #    for ( @{ $srcDirs->{$key} } ) {
        #        #print GREEN "$key  ==>  $_\n";
        #    }
        #}

        map { $$allSrcFiles{$_} = $$srcFiles{$_}; $$allSrcFilesPrefix{$_} = $sourcePath; } ( keys(%$srcFiles) );
        map { $$allSrcDirs{$_}  = $$srcDirs{$_};  $$allSrcDirsPrefix{$_}  = $sourcePath; } ( keys(%$srcDirs) );
    }

    print("INFO: Begin to compare local and remote files info...\n");
    my $needCreateTar = 1;
    my ( @updatedFiles, @newFiles, @oldFiles, @delFiles, @newDirs, @modDirs, @delDirs );
    foreach $sourcePath (@allSrcPath) {
        chdir($sourcePath);

        #找出新增的文件和更改过的文件
        foreach $srcFile ( keys(%$allSrcFiles) ) {
            if ( $$allSrcFilesPrefix{$srcFile} eq $sourcePath ) {
                if ( not exists( $$allTgtFiles{$srcFile} ) ) {
                    my $mode = ( stat($srcFile) )[2];
                    if ( defined($addExeModForNewFile) and $addExeModForNewFile == 1 and -f $srcFile ) {
                        chmod( $mode | 0755, $srcFile );
                    }
                    else {
                        chmod( $mode | 0644, $srcFile );
                    }

                    push( @updatedFiles, $srcFile );
                    push( @newFiles,     $srcFile );
                }
                else {
                    $srcStat = $$allSrcFiles{$srcFile};
                    $tgtStat = $$allTgtFiles{$srcFile};

                    if ( $$srcStat[0] ne $$tgtStat[0] ) {
                        if ( $$srcStat[1] ne $$tgtStat[1] ) {
                            my $mode = oct( $$tgtStat[1] );
                            chmod( $mode, $srcFile );
                        }

                        push( @updatedFiles, $srcFile );
                        push( @oldFiles,     $srcFile );
                    }
                    elsif ( $$srcStat[1] ne $$tgtStat[1] ) {
                        if ( not defined($noAttrs) or $noAttrs eq 0 ) {
                            if ( $$srcStat[1] ne $$tgtStat[1] and $ostype ne 'windows' ) {

                                #print("预更改$srcFile权限为", $$srcStat[1], "\n");
                                $chmodCmdStr = "chmod " . $$srcStat[1] . ' "' . $deployUtils->escapeQuote($srcFile) . qq{" || exit 1\n$chmodCmdStr};
                            }
                        }
                    }
                }
            }
        }

        #找出新增的目录
        if ( $deleteOnly == 0 ) {
            foreach $srcDir ( keys(%$allSrcDirs) ) {
                if ( $$allSrcDirsPrefix{$srcDir} eq $sourcePath ) {
                    $srcStat = $$allSrcDirs{$srcDir};
                    if ( not exists( $$allTgtDirs{$srcDir} ) ) {

                        push( @newDirs, $srcDir );

                        #print("$targetIP: 预创建目录 $targetPath/$srcDir\n");
                        if ( $ostype eq 'windows' ) {
                            my $tmp_srcDir = $srcDir;
                            $tmp_srcDir =~ s/\//\\/g;
                            $cmdStr_forwindows = "${cmdStr_forwindows}if not exist $tmp_srcDir mkdir $tmp_srcDir 1>nul 2>nul\n";
                        }
                        else {
                            $cmdStr = "${cmdStr}if [ ! -e '$srcDir' ]; then mkdir -p '$srcDir' || exit 1; fi\n";
                        }

                        if ( ( not defined($noAttrs) or $noAttrs eq 0 ) and $ostype ne 'windows' ) {

                            #print("预更改目录$srcDir权限为", $$srcStat[1], "\n");
                            $chmodCmdStr = "chmod " . $$srcStat[1] . ' "' . $deployUtils->escapeQuote($srcDir) . qq{" || exit 1\n$chmodCmdStr};
                        }
                    }
                    else {
                        $tgtStat = $$allTgtDirs{$srcDir};
                        if ( $$srcStat[1] ne $$tgtStat[1] ) {
                            if ( ( not defined($noAttrs) or $noAttrs eq 0 ) and $ostype ne 'windows' ) {
                                push( @modDirs, $srcDir );

                                #print("预更改目录$srcDir权限为", $$srcStat[1], "\n");
                                $chmodCmdStr = "chmod " . $$srcStat[1] . ' "' . $deployUtils->escapeQuote($srcDir) . qq{" || exit 1\n$chmodCmdStr};
                            }
                            else {
                                my $mode = oct( $$tgtStat[1] );
                                chmod( $mode, $srcDir );
                            }
                        }
                    }
                }
            }
        }

        #将所有需要更新的文件分批次打tar包
        if ( $self->{deleteOnly} == 0 ) {
            my $countFiles = scalar(@updatedFiles);
            for ( my $i = 0 ; $i < $countFiles ; $i += 100 ) {
                $hasTar = 1;
                my $cmd = "tar r${followLinksOpt}f $tarPath/$tarFileName";
                if ( $needCreateTar == 1 ) {
                    $cmd           = "tar -c${followLinksOpt}f $tarPath/$tarFileName";
                    $needCreateTar = 0;
                }

                my $hasTarFile = 0;
                foreach my $file ( splice( @updatedFiles, 0, 100 ) ) {
                    $hasTarFile = 1;
                    $cmd        = $cmd . ' "' . $deployUtils->escapeQuote($file) . '"';
                }
                my $rc = 0;
                if ( $hasTarFile == 1 ) {
                    $rc = $deployUtils->execmd($cmd);
                }
                if ( $rc ne 0 and $rc ne 1 ) {
                    print("ERROR: Package and update files failed.\n");
                    exit(-1);
                }
            }
        }
    }

    print("INFO: Files info cmpare and delta tar file generation complete.\n");

    #更改tar文件权限
    if ( -e "$tarPath/$tarFileName" ) {

        #$deployUtils->execmd("chmod 664 $tarPath/$tarFileName");
        chmod( 0664, "$tarPath/$tarFileName" );
        print("$targetIP:Create tar:$tarPath/$tarFileName complete.\n");
    }

    #查找出删除的文件，并生成删除的shell命令
    if ( not defined($noDelete) or $noDelete eq 0 ) {
        foreach $tgtFile ( keys(%$allTgtFiles) ) {
            if ( not exists( $$allSrcFiles{$tgtFile} ) ) {
                if ( $ostype eq 'windows' ) {
                    my $tmp_tgtFile = $tgtFile;
                    $tmp_tgtFile =~ s/\//\\/g;
                    $cmdStr = "${cmdStr}if exist \"" . $tmp_tgtFile . "\" del /q \"" . $tmp_tgtFile . "\"\n"
                        if ( $tmp_tgtFile ne $shFileName );    #防止在bat文件中出现删掉它自己的命令
                }
                else {
                    $cmdStr = qq{${cmdStr}if [ -e "} . $deployUtils->escapeQuote($tgtFile) . qq{" ]; then rm -f "} . $deployUtils->escapeQuote($tgtFile) . qq{" || exit 1; fi\n};
                }
                push( @delFiles, $tgtFile );

                #print("$targetIP: 预删除文件 $targetPath/$tgtFile\n");
            }
        }
        foreach $tgtDir ( keys(%$allTgtDirs) ) {
            if ( not exists( $$allSrcDirs{$tgtDir} ) ) {
                if ( $ostype eq 'windows' ) {
                    my $tmp_tgtDir = $tgtDir;
                    $tmp_tgtDir =~ s/\//\\/g;
                    $cmdStr = "${cmdStr}if exist \"" . $tmp_tgtDir . "\" rmdir /s /q \"" . $tmp_tgtDir . "\"\n";
                }
                else {
                    $cmdStr = qq{${cmdStr}if [ -e "} . $deployUtils->escapeQuote($tgtDir) . qq{" ]; then  rm -rf "} . $deployUtils->escapeQuote($tgtDir) . qq{" || exit 1; fi\n};
                }
                push( @delDirs, $tgtDir );

                #print("$targetIP: 预删除目录 $targetPath/$tgtDir\n");
            }
        }
    }

    if ( $ostype eq 'windows' ) { $cmdStr .= $cmdStr_forwindows }

    print("INFO: Files delete shell script generation complete.\n");

    #如果有更新的文件则将文件拷贝到远程端
    if ( $hasTar == 1 ) {
        $self->remoteCopy( $agentType, $targetUser, $targetPwd, $targetIP, "$tarPath/$tarFileName", $targetPath, 1, 0 );
        print("INFO: $targetIP: copy tar file complete.\n");
        if ( $ostype eq 'windows' ) {
            $cmdStr = $cmdStr . "7z x $tarFileName -y\n";
        }
        else {
            $cmdStr = "tar x${followLinksOpt}f $tarFileName 2>&1 || exit 1\nrm -f $tarFileName || exit 1\n" . $cmdStr;
        }
    }

    if ( $self->{deleteOnly} == 0 and $chmodCmdStr ne '' ) {
        $cmdStr = "$cmdStr\n$chmodCmdStr" if ( $ostype ne 'windows' );
    }

    #如果远程命令串非空，则连接到远程机器执行
    if ( $cmdStr ne '' ) {
        if ( $ostype ne 'windows' ) {
            $cmdStr = "umask 000\nunalias tar >/dev/null 2>\&1\n$cmdStr";
        }

        my $shFH = new IO::File(">$tarPath/$shFileName");
        if ( defined($shFH) ) {
            if ( $ostype eq 'windows' ) {
                my $temp_targetPath = $targetPath;
                $temp_targetPath =~ s/\//\\/g;
                my $driver = '';
                if ( $temp_targetPath =~ /([a-z]:)/i ) {
                    $driver = $1;
                }

                #$cmdStr = "cd /$1 $temp_targetPath\n" . $cmdStr . "if exist $tarFileName del /q $tarFileName\n";
                $cmdStr = "$driver\ncd $temp_targetPath\n" . $cmdStr . "if exist $tarFileName del /q $tarFileName\n";
                $cmdStr =~ s/\n/\r\n/g;
            }
            print $shFH ($cmdStr);
            $shFH->close();
        }
        else {
            die("ERROR: Create update script file:$tarPath/$shFileName failed");
        }

        if ( $ostype eq 'windows' ) {
            $self->remoteCopy( $agentType, $targetUser, $targetPwd, $targetIP, "$tarPath/$shFileName", $targetPath, 1, 1 );
        }
        else {
            $self->remoteCopy( $agentType, $targetUser, $targetPwd, $targetIP, "$tarPath/$shFileName", $targetPath, 1, 1 );
        }

        print("$targetIP: Copy shell script file complete.\n");

        my $cmd;
        print("\nRun script on $targetUser\@$targetIP\n");
        if ( $ostype eq 'windows' ) {
            my $tmp_targetPath = $targetPath;

            #$tmp_targetPath =~ s/\//\\\\\\\\/g;
            $tmp_targetPath =~ s/\//\\/g;

            #$cmd = "cmd /c $tmp_targetPath\\$shFileName\ncmd /c del /q $tmp_targetPath\\$shFileName\n";
            $cmd = "cmd /c \"$tmp_targetPath\\$shFileName\" \&\& cmd /c del /q \"$tmp_targetPath\\$shFileName\"\n";
            $self->execRemoteCmdWindows( $agentType, $targetUser, $targetPwd, $targetIP, $cmd, 1 );
        }
        else {
            $cmd = "cd '$targetPath' && sh $shFileName 2>&1\nrc=\$? \&\& rm -f $shFileName || exit 1\nexit \$rc\n";
            $self->execRemoteCmd( $agentType, $targetUser, $targetPwd, $targetIP, $cmd, 1 );
        }
        print("Run script on $targetUser\@$targetIP complete.\n");
    }

    print("INFO: Execute update script complete.\n");

    #将更新情况输出
    my $hasDiff = 0;
    my $hasMd5  = 0;
    my $file;
    print( "==============", $deployUtils->getDateTimeForLog(), "===============\n" );
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
        print("Del File:$file\n");
    }
    foreach $file (@newFiles) {
        print("New File:$file\n");
    }
    foreach $file (@oldFiles) {
        $hasDiff = 1;
        print("Update File:$file\n");
    }

    if ( $hasDiff == 0 ) {
        print("INFO: Source and destination directory has no difference.\n");
    }
    if ( $hasMd5 == 1 ) {
        print("INFO: Md5 check sum files not display.\n");
    }

    print("============================================\n");

    unlink("$tarPath/$shFileName");
    unlink("$tarPath/$tarFileName");
}

1;

