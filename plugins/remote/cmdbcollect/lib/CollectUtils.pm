#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package CollectUtils;

use strict;
use Encode;
use IO::File;
use POSIX qw(uname);

sub new {
    my ($type) = @_;
    my $self = {};

    my @uname  = uname();
    my $ostype = $uname[0];
    $ostype =~ s/\s.*$//;
    $self->{ostype} = $ostype;

    $self->{debug} = int( $ENV{OSCOLLECT_DEBUG} );

    $self->{isRoot} = 0;
    if ( $> == 0 ) {

        #如果EUID是0，那么运行用户就是root
        $self->{isRoot} = 1;
    }

    bless( $self, $type );
    return $self;
}

#获取windows的ps1文件内容拼装为powershell命令行
sub getWinPs1Cmd {
    my ( $self, $psPath ) = @_;

    my $cmd;
    my $fh = IO::File->new("<$psPath");
    if ($fh) {
        my $size = -s $psPath;
        $fh->read( $cmd, $size );
        $fh->close();
        $cmd =~ s/\s+/ /g;
    }
    else {
        print("WARN: Open file:$psPath for read failed, $!.\n");
    }

    $cmd =~ s/\\/\\\\/g;
    $cmd =~ s/\"/\\\"/g;
    $cmd =~ s/\&/\"\&amp;\"/g;

    $cmd = "PowerShell -Command $cmd";

    return $cmd;
}

#执行powershell脚本
sub getWinPSCmdOut {
    my ( $self, $psScript, $opts ) = @_;
    if ( not defined($opts) ) {
        $opts = {};
    }

    $psScript =~ s/\s+/ /g;
    $psScript =~ s/\\/\\\\/g;
    $psScript =~ s/\"/\\\"/g;
    $psScript =~ s/\&/\"\&amp;\"/g;

    my $cmd;
    if ( $self->{debug} ) {
        $cmd = qq{PowerShell -Command "$psScript"};
    }
    else {
        $cmd = qq{PowerShell -Command "$psScript" 2>nul};
    }

    if ( $opts->{verbose} == 1 ) {
        print("INFO:$cmd\n");
    }

    my $out    = `$cmd`;
    my $status = $?;

    if ( defined( $opts->{charset} ) ) {
        $out = Encode::encode( "utf-8", Encode::decode( $opts->{charset}, $out ) );
    }

    if ( $self->{debug} ) {
        print("DEBUG: Command output==================\n");
        print($out);
    }

    if ( $status ne 0 ) {
        print("WARN: execute powershell script:$psScript failed.\n");
    }

    chomp($out);

    return ( $status, $out );
}

#执行powershell脚本
sub getWinPSCmdOutLines {
    my ( $self, $psScript, $opts ) = @_;
    if ( not defined($opts) ) {
        $opts = {};
    }

    $psScript =~ s/\s+/ /g;
    $psScript =~ s/\\/\\\\/g;
    $psScript =~ s/\"/\\\"/g;
    $psScript =~ s/\&/\"\&amp;\"/g;

    my $cmd;
    if ( $self->{debug} ) {
        $cmd = qq{PowerShell -Command "$psScript"};
    }
    else {
        $cmd = qq{PowerShell -Command "$psScript" 2>nul};
    }

    if ( $opts->{verbose} == 1 ) {
        print("INFO:$cmd\n");
    }

    my $out    = `$cmd`;
    my $status = $?;

    if ( defined( $opts->{charset} ) ) {
        $out = Encode::encode( "utf-8", Encode::decode( $opts->{charset}, $out ) );
    }

    if ( $self->{debug} ) {
        print("DEBUG: Command output==================\n");
        print($out);
    }

    my @outLines = split( /\n/, $out );

    if ( $status ne 0 ) {
        print("WARN: execute powershell script:$psScript failed.\n");
    }

    return ( $status, \@outLines );
}

#su运行命令，并返回输出的文本
#charSet参数是用于windows的处理的，windows命令行默认是GBK
sub getCmdOut {
    my ( $self, $cmd, $user, $opts ) = @_;
    if ( not defined($opts) ) {
        $opts = {};
    }

    if ( $opts->{verbose} == 1 ) {
        print("INFO:$cmd\n");
    }

    my $out   = '';
    my $hasSu = 0;
    if ( $self->{ostype} ne 'Windows' and defined($user) ) {
        if ( $self->{isRoot} ) {
            $hasSu = 1;

            if ( $self->{debug} ) {
                print("DEBUG: Begin execute command: su - '$user' -c '$cmd'\n");
            }
            $out = `su - '$user' -c '$cmd'`;
        }
        elsif ( getpwnam($user) == $> ) {

            #如果运行目标用户是当前用户，$>:EFFECTIVE_USER_ID
            if ( $self->{debug} ) {
                print("DEBUG: Begin execute command: $cmd\n");
            }
            $out = `$cmd`;
        }
        else {
            print("WARN: Can not execute command:$cmd by user $user.\n");
        }
    }
    else {
        if ( $self->{debug} ) {
            print("DEBUG: Begin execute command: $cmd\n");
        }
        $out = `$cmd`;
    }

    my $status = $?;

    if ( defined( $opts->{charset} ) ) {
        $out = Encode::encode( "utf-8", Encode::decode( $opts->{charset}, $out ) );
    }

    if ( $self->{debug} ) {
        print("DEBUG: Command output==================\n");
        print($out);
    }

    if ( $status ne 0 and not defined( $opts->{nowarn} ) ) {
        if ( $hasSu == 1 ) {
            print("WARN: Execute Command:$cmd by $user failed.\n");
        }
        else {
            print("WARN: Execute command:$cmd failed.\n");
        }
    }

    if ( $opts->{verbose} == 1 ) {
        print("INFO:$cmd finished.\n");
    }

    chomp($out);
    return ( $status, $out );
}

#su运行命令，并返回输出的行数组
#charSet参数是用于windows的处理的，windows命令行默认是GBK
sub getCmdOutLines {
    my ( $self, $cmd, $user, $opts ) = @_;
    if ( not defined($opts) ) {
        $opts = {};
    }

    if ( $opts->{verbose} == 1 ) {
        print("INFO:$cmd\n");
    }

    my @out   = ();
    my $hasSu = 0;
    if ( $self->{ostype} ne 'Windows' and defined($user) ) {
        if ( $self->{isRoot} ) {
            $hasSu = 1;

            if ( $self->{debug} ) {
                print("DEBUG: Begin execute command: su - '$user' -c '$cmd'\n");
            }
            @out = `su - '$user' -c '$cmd'`;
        }
        elsif ( getpwnam($user) == $> ) {
            if ( $self->{debug} ) {
                print("DEBUG: Begin execute command: $cmd\n");
            }

            #如果运行目标用户是当前用户，$>:EFFECTIVE_USER_ID
            @out = `$cmd`;
        }
        else {
            print("WARN: Can not execute command:$cmd by user $user.\n");
        }
    }
    else {
        if ( $self->{debug} ) {
            print("DEBUG: Begin execute command: $cmd\n");
        }
        @out = `$cmd`;
    }

    my $status = $?;

    if ( defined( $opts->{charset} ) ) {
        for ( my $i = 0 ; $i <= $#out ; $i++ ) {
            $out[$i] = Encode::encode( "utf-8", Encode::decode( $opts->{charset}, $out[$i] ) );
        }
    }

    if ( $self->{debug} ) {
        print("DEBUG: Command output==================\n");
        foreach my $line (@out) {
            print($line);
        }
    }

    if ( $status ne 0 and not defined( $opts->{nowarn} ) ) {
        if ( $hasSu == 1 ) {
            print("WARN: Execute Command:$cmd by $user failed.\n");
        }
        else {
            print("WARN: Execute Command:$cmd failed.\n");
        }
    }

    if ( $opts->{verbose} == 1 ) {
        print("INFO:$cmd finished.\n");
    }

    return ( $status, \@out );
}

sub getFileContent {
    my ( $self, $filePath ) = @_;

    if ( $self->{debug} ) {
        print("DEBUG: Begin to read file:$filePath...\n");
    }

    my $fh = IO::File->new( $filePath, 'r' );
    my $content;
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            $content = $content . $line;
        }
        $fh->close();

        if ( $self->{debug} ) {
            print("DEBUG: Read file:$filePath success.\n");
        }
    }
    else {
        print("WARN: Can not open file:$filePath $!\n");
    }

    return $content;
}

#读取文件所有行
sub getFileLines {
    my ( $self, $filePath ) = @_;
    my @lines;

    if ( $self->{debug} ) {
        print("DEBUG: Begin to read file:$filePath...\n");
    }

    my $fh = IO::File->new( $filePath, 'r' );
    if ( defined($fh) ) {
        my $line;
        while ( $line = $fh->getline() ) {
            push( @lines, $line );
        }
        $fh->close();

        if ( $self->{debug} ) {
            print("DEBUG: Read file:$filePath success.\n");
        }
    }
    else {
        print("WARN: Can not open file:$filePath $!\n");
    }

    return \@lines;
}

#转换带不确定单位的磁盘空间字串为数值，对应标准单位GB
#譬如：297348 MB：转换为：197.349、 937493 TB：转换为937493000
sub getDiskSizeFormStr {
    my ( $self, $sizeStr ) = @_;
    chomp($sizeStr);
    $sizeStr =~ s/,//g;
    my $size;
    my $unit = 'GB';
    if ( $sizeStr =~ /K|KB|KiB$/i ) {
        $size = int( $sizeStr / 1000 + 0.5 ) / 1000;
    }
    elsif ( $sizeStr =~ /M|MB|MiB$/i ) {
        $size = int( $sizeStr + 0.5 ) / 1000;
    }
    elsif ( $sizeStr =~ /G|GB|GiB$/i ) {
        $size = $sizeStr + 0.0;
    }
    elsif ( $sizeStr =~ /T|TB|TiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1000;
    }
    elsif ( $sizeStr =~ /P|PB|PiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1000 * 1000;
    }
    elsif ( $sizeStr =~ /\d$/i ) {

        #默认是GB
        $size = $sizeStr + 0.0;
    }
    else {
        $size = $sizeStr;
        $unit = 'unknown';
    }

    return ( $unit, $size );
}

#转换带不确定单位的内存空间字串为数值，对应标准单位MB
#譬如：10240 KB：转换为：10、 10 GB：转换为10240
sub getMemSizeFromStr {
    my ( $self, $sizeStr, $defaultUnit ) = @_;
    chomp($sizeStr);
    $sizeStr =~ s/,//g;

    if ( defined($defaultUnit) and $sizeStr =~ /\d$/ ) {
        $sizeStr = $sizeStr . $defaultUnit;
    }

    my $size;
    my $unit = 'GB';
    if ( $sizeStr =~ /K|KB|KiB$/i ) {
        $size = int( ( $sizeStr + 0.0 ) / 1024 * 1000 + 0.5 ) / 1000;
    }
    elsif ( $sizeStr =~ /M|MB|MiB$/i ) {
        $size = $sizeStr + 0.0;
    }
    elsif ( $sizeStr =~ /G|GB|GiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1024;
    }
    elsif ( $sizeStr =~ /T|TB|TiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1024 * 1024;
    }
    elsif ( $sizeStr =~ /P|PB|PiB$/i ) {
        $size = ( $sizeStr + 0.0 ) * 1024 * 1024 * 1024;
    }
    elsif ( $sizeStr =~ /\d$/i ) {

        #默认是MB
        $size = $sizeStr + 0.0;
    }
    else {
        $size = $sizeStr;
        $unit = 'unknown';
    }

    return ( $unit, $size );
}

#转换带不确定单位的网络速度字串为数值，对应标准单位Mb/s
#譬如：297348 Kb/s：转换为：197.349、 937493 Gb/s：转换为937493000
sub getNicSpeedFromStr {
    my ( $self, $speedStr ) = @_;
    chomp($speedStr);
    $speedStr =~ s/,//g;
    my $speed;
    my $unit = 'Mb/s';
    if ( $speedStr =~ /K|Kb/i ) {
        $speed = int($speedStr) / 1000;
    }
    elsif ( $speedStr =~ /M|Mb/i ) {
        $speed = $speedStr + 0.0;
    }
    elsif ( $speedStr =~ /G|Gb/i ) {
        $speed = ( $speedStr + 0.0 ) * 1000;
    }
    elsif ( $speedStr =~ /T|Tb/i ) {
        $speed = ( $speedStr + 0.0 ) * 1000 * 1000;
    }
    elsif ( $speedStr =~ /P|Pb/i ) {
        $speed = ( $speedStr + 0.0 ) * 1000 * 1000 * 1000;
    }
    elsif ( $speedStr =~ /\d$/i ) {

        #默认是Kb/s
        $speed = int($speedStr) / 1000;
    }
    else {
        $speed = $speedStr;
        $unit  = 'unknown';
    }

    return ( $unit, $speed );
}

sub getExecutablePath {
    my ( $self, $pid ) = @_;
    my $ostype = $self->{ostype};
    my $executablePath;
    if ( $ostype eq 'Windows' ) {
        my $lines = $self->getCmdOutLines(qq{wmic process where "ProcessID=$pid" get ExecutablePath});
        if ( scalar(@$lines) >= 2 ) {
            $executablePath = $$lines[1];
            $executablePath =~ s/^\s*|\s*$//g;
        }
    }
    else {
        if ( -e "/proc/$pid/exe" ) {
            $executablePath = readlink("/proc/$pid/exe");
        }
    }

    return $executablePath;
}

1;
