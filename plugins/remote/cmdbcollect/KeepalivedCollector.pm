#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package KeepalivedCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;
#use Data::Dumper;

sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\bkeepalived\s'],
        psAttrs  => { COMM => 'keepalived' },
        envAttrs => {}
    };
}

sub getPK {
    my ($self) = @_;
    return { $self->{defaultAppType} => ['INBOUND_IP'] };
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }
    my $procInfo       = $self->{procInfo};
    my $keepalivedInfo = {};
    $keepalivedInfo->{OBJECT_TYPE} = $CollectObjType::APP;
    $keepalivedInfo->{SERVER_NAME} = 'keepalived';

    my $exePath  = $procInfo->{EXECUTABLE_FILE};
    my $binPath  = dirname($exePath);
    my $basePath = dirname($binPath);
    chdir($binPath);
    my ( $version, $prefix );
    my @keepalived_info = `./keepalived -v |& awk '{print \$0}'`;
    foreach my $line (@keepalived_info) {
        if ( $line =~ /Keepalived/ ) {
            my $e = rindex( $line, '(' );
            $version = substr( $line, 0, $e );
            $version =~ s/Keepalived//;
            $version = str_trim($version);
        }
        if ( $line =~ /configure options/ ) {
            my @values = str_split( $line, ':' );
            my $cfg    = @values[1];
            $cfg = str_trim($cfg);
            if ( $cfg =~ /--prefix=/ ) {
                my @values = str_split( $cfg, '=' );
                $prefix = @values[1] || '';
                $prefix = str_trim($prefix);
            }
        }
    }
    my $configPath = File::Spec->catfile("/etc/keepalived/");
    my $configFile = File::Spec->catfile( $configPath, "keepalived.conf" );

    $keepalivedInfo->{EXE_PATH}      = $exePath;
    $keepalivedInfo->{BIN_PATH}      = $binPath;
    $keepalivedInfo->{INSTALL_PATH}  = $basePath;
    $keepalivedInfo->{VERSION}       = $version;
    $keepalivedInfo->{PREFIX}        = $prefix;
    $keepalivedInfo->{CONFIG_PATH}   = $configPath;
    $keepalivedInfo->{VRRP_SCRIPT}   = parseConfig( $configFile, 'vrrp_script' );
    $keepalivedInfo->{VRRP_INSTANCE} = parseConfig( $configFile, 'vrrp_instance' );
    $keepalivedInfo->{MON_PORT}      = undef;
    return $keepalivedInfo;
}

sub parseConfig {
    my ( $conf_path, $identification ) = @_;
    my @vrrp       = parseVrrp( $conf_path, $identification );
    my @vrrpResult = ();
    foreach my $content (@vrrp) {
        my $instance = parseStructure( $content, $identification );
        push( @vrrpResult, $instance );
    }
    return \@vrrpResult;
}

sub formatStructure {
    my ( $content, $identification ) = @_;
    my $newContent = '';
    while (1) {
        my $index       = index( $content, $identification );
        my $block       = substr( $content, 0, $index + 1 );
        my @block_array = str_split( $block, '\n' );
        my $newBlock    = '';
        foreach my $line (@block_array) {
            chomp($line);
            $line =~ s/^\s+//g;
            $line =~ ~s/\s+$//g;
            if ( $line eq '' or $line =~ /^#/ ) {
                next;
            }
            if ( $line !~ /^#/ and $line eq $identification ) {
                $newBlock = $newBlock . $line;
            }
            else {
                $newBlock = $newBlock . "\n" . $line;
            }
        }
        $block =~ s/\n/ /;
        $block =~ s/\r/ /;
        $newContent = $newContent . $newBlock;
        $content    = substr( $content, $index + 1, length($content) );
        if ( $index == -1 ) {
            $newContent = $newContent . $content;
            last;
        }
    }
    return $newContent;
}

sub parseStructure {
    my ( $content, $identification ) = @_;
    my $instance = {};
    my $index    = 0;
    my $name;
    $content =~ s/$identification//g;
    $index            = index( $content, '{' );
    $name             = substr( $content, 0, $index );
    $instance->{NAME} = str_trim($name);
    $content          = substr( $content, $index + 1, length($content) );

    #分析正文
    my @contents = str_split( $content, '[\n\r]' );
    my $block    = '';
    my ( $startIndex, $endIndex ) = ( 0, 0 );
    foreach my $line (@contents) {
        chomp($line);
        $line =~ s/^\s+//g;
        $line =~ ~s/\s+$//g;

        #去掉配置文件注释
        my $notesIndex = index( $line, '#' );
        if ( $notesIndex > 0 ) {
            $line = substr( $line, 0, $notesIndex );
        }
        if ( index( $line, '{' ) > 0 ) {
            $startIndex = 1;
        }
        elsif ( ( $line !~ /^#/ and index( $line, '}' ) > 0 ) or $line eq '}' ) {
            $endIndex = 1;
        }
        if ( $startIndex == 1 ) {
            $block = $block . "\n" . $line;
        }
        elsif ( $endIndex == 1 ) {
            $block = $block . "\n" . $line;
        }
        if ( $line eq '' or $line =~ /^#/ ) {
            next;
        }

        #常规文本
        if ( $startIndex == 0 and $endIndex == 0 and $block eq '' ) {
            my @values = str_split( $line, '\s+' );
            if ( scalar(@values) > 1 ) {
                my $key   = str_trim( @values[0] );
                my $value = str_trim( @values[1] );
                $instance->{ uc($key) } = $value;
            }
            else {
                $instance->{ str_trim($line) } = str_trim($line);
            }
        }

        #结构化配置
        if ( $startIndex == 1 and $endIndex == 1 and $block ne '' ) {
            my ( $key, $value ) = analysisValue($block);
            $instance->{ uc($key) } = $value;
            $startIndex             = 0;
            $endIndex               = 0;
            $block                  = '';
        }
    }
    return $instance;
}

sub analysisValue {
    my ($content) = @_;
    my $instance  = {};
    my $index     = 0;
    my $name;
    $index   = index( $content, '{' );
    $name    = substr( $content, 0,      $index );
    $content = substr( $content, $index, length($content) );
    $content =~ ~s/^\s+|\s+$//g;
    $content =~ s/\{//g;
    $content =~ s/\}//g;
    my @contents = str_split( $content, '[\n\r]' );

    foreach my $line (@contents) {
        chomp($line);
        my $notesIndex = index( $line, '#' );
        if ( $notesIndex > 0 ) {
            $line = substr( $line, 0, $notesIndex );
        }
        $line =~ s/^\s+//g;
        $line =~ ~s/\s+$//g;
        if ( $line eq '' or $line =~ /^#/ ) {
            next;
        }
        my @values = str_split( $line, '\s+' );
        if ( scalar(@values) > 1 ) {
            my $key   = str_trim( @values[0] );
            my $value = str_trim( @values[1] );
            $instance->{ uc($key) } = $value;
        }
        else {
            $instance = [ str_trim($line) ];
        }
    }
    return ( str_trim($name), $instance );
}

sub parseVrrp {
    my ( $confPath, $identification ) = @_;
    my @vrrp       = ();
    my $info       = '';
    my $startCount = 0;
    my $endCount   = 0;
    my $fh         = IO::File->new( $confPath, 'r' );
    if ( defined($fh) ) {
        my $fileSize = -s $confPath;
        my $fileContent;
        $fh->read( $fileContent, $fileSize );
        $fileContent = formatStructure( $fileContent, '{' );

        #        $fileContent = formatStructure( $fileContent, '}' );
        my @contents = str_split( $fileContent, '\n' );
        foreach my $read_line (@contents) {
            chomp($read_line);

            if ( ( $read_line =~ /$identification/ and $read_line =~ /\{/ ) or ( $startCount > 0 and $read_line =~ /\{/ ) ) {
                $startCount = $startCount + 1;
            }
            if ( $startCount > 0 and $read_line =~ /\}/ ) {
                $endCount = $endCount + 1;
            }

            if ( $startCount > 0 and $startCount >= $endCount ) {
                $info = $info . "\n" . $read_line;
            }

            if ( $startCount == $endCount and $info ne '' ) {
                push( @vrrp, $info );
                $info       = '';
                $startCount = 0;
                $endCount   = 0;
            }
        }
        $fh->close;
    }
    return @vrrp;
}

sub str_split {
    my ( $str, $separator ) = @_;
    my @values = split /$separator/, $str;
    return @values;
}

sub str_trim {
    my ($str) = @_;
    $str =~ s/^\s+|\s+$//g;
    $str =~ s/[\r\n]$//;
    return $str;
}

1;
