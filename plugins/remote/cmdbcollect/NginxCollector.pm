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
use CollectObjCat;
use Data::Dumper;

sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\bmaster process\s'],
        psAttrs  => { COMM => 'nginx' },
        envAttrs => {}
    };
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }
    my $procInfo = $self->{procInfo};
    my $command  = $procInfo->{COMMAND};

    my $nginxInfo = {};
    $nginxInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');
    $nginxInfo->{SERVER_NAME}   = 'nginx';

    my $exePath = $procInfo->{EXECUTABLE_FILE};
    if ( $command =~ /^.*?(\/.*?\/nginx)(?=\s)/ or $command =~ /^.*?(\/.*?\/nginx)$/ ) {
        $exePath = $1;
    }

    my $pid      = $procInfo->{PID};
    my $workPath = readlink("/proc/$pid/cwd");
    my $binPath  = dirname($exePath);
    my $basePath = dirname($binPath);
    my ( $version, $prefix );
    my $nginxInfoLines = $self->getCmdOutLines("$binPath/nginx -V 2>&1");
    foreach my $line (@$nginxInfoLines) {
        if ( $line =~ /nginx version:/ ) {
            my @values = split( /:/, $line );
            $version = $values[1] || '';
            $version =~ s/nginx\///g;
            $version =~ s/^\s+|\s+$//g;
        }
        if ( $line =~ /configure arguments:/ ) {
            my @values = split( /:/, $line );
            my $cfg = $values[1];
            $cfg =~ s/^\s+|\s+$//g;
            if ( $cfg =~ /--prefix=/ ) {
                my @values = split( /=/, $cfg );
                $prefix = $values[1] || '';
                $prefix =~ s/^\s+|\s+$//g;
            }
        }
    }

    my $configPath;
    my $configFile;
    if ( $command =~ /\s-c\s+(.*?)\s+-/ or $command =~ /\s-c\s+(.*?)\s*$/ ) {
        $configFile = $1;
        if ( $configFile !~ /^\// ) {
            $configFile = "$workPath/$configFile";
        }
        $configPath = dirname($configFile);
    }
    else {
        $configPath = File::Spec->catfile( $basePath,   "conf" );
        $configFile = File::Spec->catfile( $configPath, "nginx.conf" );
    }

    $nginxInfo->{EXE_PATH}     = $exePath;
    $nginxInfo->{BIN_PATH}     = $binPath;
    $nginxInfo->{INSTALL_PATH} = $basePath;
    $nginxInfo->{VERSION}      = $version;
    $nginxInfo->{PREFIX}       = $prefix;
    $nginxInfo->{CONFIG_PATH}  = $configPath;
    $nginxInfo->{SERVERS}      = parseConfig( $self, $configFile );

    my $lsnPortsMap = $procInfo->{CONN_INFO}->{LISTEN};
    my $minPort     = 65535;
    my @ports       = ();
    foreach my $lsnPort ( keys(%$lsnPortsMap) ) {
        if ( $lsnPort =~ /:(\d+)$/ ) {
            push( @ports, int($1) );
        }
        elsif ( $lsnPort < $minPort ) {
            push( @ports, $lsnPort );
            $minPort = int($lsnPort);
        }
    }

    $nginxInfo->{PORT}     = $minPort;
    $nginxInfo->{MON_PORT} = $minPort;
    $nginxInfo->{PORTS}    = \@ports;
    return $nginxInfo;
}

sub parseConfigServer {
    my ( $self, $confPath ) = @_;
    my @serverCfg  = ();
    my $server     = '';
    my $startCount = 0;
    my $endCount   = 0;
    my $contents   = $self->getFileLines($confPath);
    foreach my $line (@$contents) {
        $line =~ s/^\s*|\s*$//g;

        if ( ( $line =~ /server/ and $line =~ /\{/ ) or ( $startCount > 0 and $line =~ /\{/ ) ) {
            $startCount = $startCount + 1;
        }
        if ( $startCount > 0 and $line =~ /\}/ ) {
            $endCount = $endCount + 1;
        }

        if ( $startCount > 0 and $startCount >= $endCount ) {
            $server = $server . "\n" . $line;
        }

        if ( $startCount == $endCount and $server ne '' ) {
            push( @serverCfg, $server );
            $server     = '';
            $startCount = 0;
            $endCount   = 0;
        }
    }
    return \@serverCfg;
}

sub parseConfigInclude {
    my ( $self, $confPath ) = @_;
    my @includes = ();
    push( @includes, $confPath );
    my $contents = $self->getFileLines($confPath);
    for my $line (@$contents) {
        $line =~ s/^\s*|\s*$//g;

        if ( $line =~ /include/ and $line !~ /mime.types/ ) {
            my $path = $line;
            $path =~ s/include//;
            $path =~ s/;//;
            $path =~ s/^\s+|\s+$//g;
            my $e = rindex( $path, '/' );
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
    my ( $self, $data, $cfg ) = @_;
    my @lines = split( /[\r\n]+/, $data );
    my $nginx = {};
    $nginx->{CONFIG_PATH} = $cfg;
    my $port       = '';
    my $serverName = '';
    my $type       = 'http';
    my $status     = 'off';

    foreach my $line (@lines) {
        $line =~ s/^\s*|\s*$//g;

        if ( $line =~ /listen/ ) {
            if ( $line =~ /(\d+)/ ) {
                $port = int($1);
            }
        }

        if ( $line =~ /server_name/ ) {
            $serverName = $line;
            $serverName =~ s/;//;
            $serverName =~ s/^\s+|\s+$//g;
        }

        if ( $line =~ /ssl/ ) {
            $type = 'https';
        }

        if ( $line =~ /\/status/ ) {
            $status = 'on';
        }
    }
    $nginx->{SERVICE_PORT}   = $port;
    $nginx->{SERVICE_NAME}   = $serverName;
    $nginx->{SERVICE_TYPE}   = $type;
    $nginx->{SERVICE_STATUS} = $status;
    return $nginx;
}

sub parseConfig {
    my ( $self, $conf_path ) = @_;
    my @includes = parseConfigInclude( $self, $conf_path );
    my @nginx_servers = ();
    foreach my $cfg (@includes) {
        my $serverCfg = parseConfigServer( $self, $cfg );
        foreach my $server (@$serverCfg) {
            $server =~ s/^\s*|\s*$//g;
            my $param = parseConfigParam( $self, $server, $cfg );
            push( @nginx_servers, $param );
        }
    }
    return \@nginx_servers;
}

1;
