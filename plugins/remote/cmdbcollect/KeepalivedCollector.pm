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
use CollectObjCat;

sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\bkeepalived\s'],
        psAttrs  => { COMM => 'keepalived' },
        envAttrs => {}
    };
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }
    my $procInfo       = $self->{procInfo};
    my $keepalivedInfo = {};
    $keepalivedInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');
    $keepalivedInfo->{SERVER_NAME}   = 'keepalived';

    my $exePath  = $procInfo->{EXECUTABLE_FILE};
    my $binPath  = dirname($exePath);
    my $basePath = dirname($binPath);
    my ( $version, $prefix );
    my $keepalived_info = $self->getCmdOutLines("$binPath/keepalived -v 2>&1");
    foreach my $line (@$keepalived_info) {
        if ( $line =~ /Keepalived/ ) {
            my $e = rindex( $line, '(' );
            $version = substr( $line, 0, $e );
            $version =~ s/Keepalived//g;
            $version =~ s/^\s*|\s*$//g;
        }
        if ( $line =~ /configure options/ ) {
            my @values = split( /:/, $line );
            my $cfg    = $values[1] || '';
            $cfg =~ s/^\s*|\s*$//g;
            if ( $cfg =~ /--prefix=/ ) {
                my @values = split( /=/, $cfg );
                $prefix = $values[1] || '';
                $prefix =~ s/^\s*|\s*$//g;
            }
        }
    }
    my $configPath = File::Spec->catfile("/etc/keepalived/");
    my $configFile = File::Spec->catfile( $configPath, "keepalived.conf" );

    $keepalivedInfo->{EXE_PATH}     = $exePath;
    $keepalivedInfo->{BIN_PATH}     = $binPath;
    $keepalivedInfo->{INSTALL_PATH} = $basePath;
    $keepalivedInfo->{VERSION}      = $version;
    if ( $version =~ /(\d+)/ ) {
        $keepalivedInfo->{MAJOR_VERSION} = "Keepalived$1";
    }

    $keepalivedInfo->{PREFIX}        = $prefix;
    $keepalivedInfo->{CONFIG_PATH}   = $configPath;
    $keepalivedInfo->{VRRP_SCRIPT}   = $self->parseConfig( $configFile, 'vrrp_script' );
    $keepalivedInfo->{VRRP_INSTANCE} = $self->parseConfig( $configFile, 'vrrp_instance' );
    $keepalivedInfo->{PORT}          = 0;
    return $keepalivedInfo;
}

sub parseConfig {
    my ( $self, $conf_path, $identification ) = @_;
    my @vrrp       = $self->parseVrrp( $conf_path, $identification );
    my @vrrpResult = ();
    foreach my $content (@vrrp) {
        my $instance = $self->parseStructure( $content, $identification );
        push( @vrrpResult, $instance );
    }
    return \@vrrpResult;
}

sub formatStructure {
    my ( $self, $content, $identification ) = @_;
    my $newContent = '';
    while (1) {
        my $index       = index( $content, $identification );
        my $block       = substr( $content, 0, $index + 1 );
        my @block_array = split( '\n', $block );
        my $newBlock    = '';
        foreach my $line (@block_array) {
            $line =~ s/^\s*|\s*$//g;
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
    my ( $self, $content, $identification ) = @_;
    my $instance = {};
    my $index    = 0;
    my $name;
    $content =~ s/$identification//g;
    $index = index( $content, '{' );
    $name  = substr( $content, 0, $index );
    $name =~ s/^\s*|\s*$//g;
    $instance->{NAME} = $name;
    $content = substr( $content, $index + 1, length($content) );

    #分析正文
    my @contents = split( '[\n\r]', $content );
    my $block    = '';
    my ( $startIndex, $endIndex ) = ( 0, 0 );
    foreach my $line (@contents) {
        $line =~ s/^\s*|\s*$//g;

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
            my @values = split( /\s+/, $line );
            if ( scalar(@values) > 1 ) {
                my $key   = $values[0];
                my $value = $values[1];
                $instance->{ uc($key) } = $value;
            }
            else {
                $line =~ s/^\s*|\s*$//g;
                $instance->{$line} = $line;
            }
        }

        #结构化配置
        if ( $startIndex == 1 and $endIndex == 1 and $block ne '' ) {
            my ( $key, $value ) = $self->analysisValue($block);
            $instance->{ uc($key) } = $value;
            $startIndex             = 0;
            $endIndex               = 0;
            $block                  = '';
        }
    }
    return $instance;
}

sub analysisValue {
    my ( $self, $content ) = @_;
    my $instance = {};
    my $index    = index( $content, '{' );
    my $name     = substr( $content, 0, $index );
    $name =~ s/^\s*|\s*$//g;

    $content = substr( $content, $index, length($content) );
    $content =~ s/^\s+|\s+$//g;
    $content =~ s/\{//g;
    $content =~ s/\}//g;
    my @contents = split( /[\n\r]/, $content );

    foreach my $line (@contents) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line eq '' or $line =~ /^#/ ) {
            next;
        }
        my @values = split( /\s+/, $line );
        if ( scalar(@values) > 1 ) {
            my $key   = $values[0];
            my $value = $values[1];
            $instance->{ uc($key) } = $value;
        }
        else {
            $instance = [$line];
        }
    }
    return ( $name, $instance );
}

sub parseVrrp {
    my ( $self, $confPath, $identification ) = @_;
    my @vrrp        = ();
    my $info        = '';
    my $startCount  = 0;
    my $endCount    = 0;
    my $fileContent = $self->getFileContent($confPath);
    $fileContent = $self->formatStructure( $fileContent, '{' );

    #        $fileContent = formatStructure($self, $fileContent, '}' );
    my @contents = split( '\n', $fileContent );
    foreach my $read_line (@contents) {
        $read_line =~ s/^\s*|\s*$//g;

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
    return @vrrp;
}

1;
