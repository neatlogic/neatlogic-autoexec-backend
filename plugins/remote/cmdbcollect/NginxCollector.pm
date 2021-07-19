#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package NginxCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\bmaster process\s'],
        psAttrs  => { COMM => 'nginx' },
        envAttrs => {}
    };
}

sub getPK {
    my ($self) = @_;
    return { $self->{defaultAppType} => ['MGMT_IP'] };
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }
    my $procInfo  = $self->{procInfo};
    my $nginxInfo = {};
    $nginxInfo->{OBJECT_TYPE} = $CollectObjType::APP;
    $nginxInfo->{SERVER_NAME} = 'nginx';

    my $exePath  = $procInfo->{EXECUTABLE_FILE};
    my $binPath  = dirname($exePath);
    my $basePath = dirname($binPath);
    chdir($binPath);
    my ( $version, $prefix );
    my @nginx_info = `./nginx -V |& awk '{print \$0}'`;
    foreach my $line (@nginx_info) {
        if ( $line =~ /nginx version:/ ) {
            my @values = str_split( $line, ':' );
            $version = @values[1] || '';
            $version = str_trim($version);
        }
        if ( $line =~ /configure arguments:/ ) {
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
    my $configPath = File::Spec->catfile( $basePath,   "conf" );
    my $configFile = File::Spec->catfile( $configPath, "nginx.conf" );

    $nginxInfo->{EXE_PATH}     = $exePath;
    $nginxInfo->{BIN_PATH}     = $binPath;
    $nginxInfo->{INSTALL_PATH} = $basePath;
    $nginxInfo->{VERSION}      = $version;
    $nginxInfo->{PREFIX}       = $prefix;
    $nginxInfo->{CONFIG_PATH}  = $configPath;
    $nginxInfo->{SERVERS}      = parseConfig($configFile);
    $nginxInfo->{MON_PORT}     = undef;
    return $nginxInfo;
}

sub parseConfigServer {
    my ($confPath) = @_;
    my @server_cfg = ();
    my $server     = '';
    my $startCount = 0;
    my $endCount   = 0;
    my @contents   = getFileContents($confPath);
    foreach my $read_line (@contents) {
        chomp($read_line);

        if ( ( $read_line =~ /server/ and $read_line =~ /\{/ ) or ( $startCount > 0 and $read_line =~ /\{/ ) ) {
            $startCount = $startCount + 1;
        }
        if ( $startCount > 0 and $read_line =~ /\}/ ) {
            $endCount = $endCount + 1;
        }

        if ( $startCount > 0 and $startCount >= $endCount ) {
            $server = $server . "\n" . $read_line;
        }

        if ( $startCount == $endCount and $server ne '' ) {
            push( @server_cfg, $server );
            $server     = '';
            $startCount = 0;
            $endCount   = 0;
        }
    }
    return @server_cfg;
}

sub parseConfigInclude {
    my ($confPath) = @_;
    my @includes = ();
    push( @includes, $confPath );
    my @contents = getFileContents($confPath);
    for my $read_line (@contents) {
        chomp($read_line);
        if ( $read_line =~ /include/ and $read_line !~ /mime.types/ ) {
            my $path = $read_line;
            $path =~ s/include//;
            $path =~ s/;//;
            $path = str_trim($path);
            my $e    = rindex( $path, '/' );
            my $dir  = substr( $path, 0,      $e );
            my $file = substr( $path, $e + 1, length($path) );
            if ( -d $dir ) {
                $dir = $dir;
            }
            else {
                my $root = dirname($confPath);
                $dir = File::Spec->catfile( $root, $dir );
            }
            if ( $file =~ /\*/ ) {
                $dir = $dir . "/" . $file;
                my @files = glob($dir);
                foreach my $file (@files) {
                    push( @includes, $file );
                }
            }
            else {
                my $tmp = File::Spec->catfile( $dir, $file );
                if ( -e $tmp ) {
                    push( @includes, $tmp );
                }
            }
        }
    }
    return @includes;
}

sub parseConfigParam {
    my ( $data, $cfg ) = @_;
    my @lines = split( /[\r\n]+/, $data );
    my $nginx = {};
    $nginx->{'CONFIG_PATH'} = $cfg;
    my $port        = '';
    my $server_name = '';
    my $type        = 'http';
    my $status      = 'off';

    foreach my $line (@lines) {
        chomp($line);
        if ( $line =~ /listen/ ) {
            $port = $line;
            $port =~ /(\d+)/;
            $port = str_trim($1);
        }

        if ( $line =~ /server_name/ ) {
            $server_name = $line;
            $server_name =~ s/;//;
            $server_name = str_trim($server_name);
        }

        if ( $line =~ /ssl/ ) {
            $type = 'https';
        }

        if ( $line =~ /\/status/ ) {
            $status = 'on';
        }
    }
    $nginx->{SERVICE_PORT} = $port;
    $nginx->{SERVICE_NAME}   = $server_name;
    $nginx->{SERVICE_TYPE}   = $type;
    $nginx->{SERVICE_STATUS} = $status;
    return $nginx;
}

sub getFileContents {
    my ($confPath) = @_;
    my $fh = IO::File->new( $confPath, 'r' );
    my $fileContent;
    my $fileSize = -s $confPath;
    if ( defined($fh) ) {
        $fh->read( $fileContent, $fileSize );
        $fh->close;
    }
    my @contents = ();
    if ( defined($fileContent) ) {
        @contents = str_split( $fileContent, '\n' );
    }
    return @contents;
}

sub parseConfig {
    my ($conf_path)   = @_;
    my @includes      = parseConfigInclude($conf_path);
    my @nginx_servers = ();
    foreach my $cfg (@includes) {
        my @server_cfg = parseConfigServer($cfg);
        foreach my $server (@server_cfg) {
            chomp($server);
            my $param = parseConfigParam( $server, $cfg );
            push( @nginx_servers, $param );
        }
    }
    return \@nginx_servers;
}

sub str_split {
    my ( $str, $separator ) = @_;
    my @values = split /$separator/, $str;
    return @values;
}

sub str_trim {
    my ($str) = @_;
    $str =~ s/^\s+|\s+$//g;
    return $str;
}

1;
