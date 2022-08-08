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
use Config::Neat;
use Data::Dumper;

sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\b(master|worker) process\s'],
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
            my $cfg    = $values[1];
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
    $self->{'configPath'} = $configPath;
    $self->{'configFile'} = $configFile;

    my $MGMT_PORT = $procInfo->{MGMT_PORT};
    my $MGMT_IP   = $procInfo->{MGMT_IP};

    my $cfg  = Config::Neat->new();
    my $data = $cfg->parse_file($configFile);

    my $worker_connections   = getStringValue( $self, $data->{'events'}, 'worker_connections', '1024' );
    my $worker_processes     = getStringValue( $self, $data,             'worker_processes',   '1' );
    my $http                 = $data->{'http'};
    my $default_type         = getStringValue( $self, $http, 'default_type' );
    my $client_max_body_size = getStringValue( $self, $http, 'client_max_body_size', '1m' );
    my $sendfile             = getStringValue( $self, $http, 'sendfile',             'on' );
    my $tcp_nopush           = getStringValue( $self, $http, 'tcp_nopush',           'off' );
    my $gzip                 = getStringValue( $self, $http, 'gzip',                 'off' );
    my @upstream             = getUpstream( $self, $http, 'upstream' );

=pod
    my $nginxInfo = {};
    $nginxInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');
    $nginxInfo->{SERVER_NAME}   = 'nginx';
    $nginxInfo->{EXE_PATH}     = $exePath;
    $nginxInfo->{BIN_PATH}     = $binPath;
    $nginxInfo->{INSTALL_PATH} = $basePath;
    $nginxInfo->{VERSION}      = $version;
    $nginxInfo->{PREFIX}       = $prefix;
    $nginxInfo->{CONFIG_PATH}  = $configPath;
    $nginxInfo->{WORKER_CONNECTIONS}  = $worker_connections ;
    $nginxInfo->{WORKER_PROCESSES}  = $worker_processes ;
    $nginxInfo->{DEFAULT_TYPE}  = $default_type ;
    $nginxInfo->{CLIENT_MAX_BODY_SIZE}  = $client_max_body_size ;
    $nginxInfo->{SENDFILE}  = $sendfile ;
    $nginxInfo->{TCP_NOPUSH}  = $tcp_nopush ;
    $nginxInfo->{GZIP}  = $gzip ;
    $nginxInfo->{UPSTREAM}  = \@upstream ;
=cut

    my $variable = getSetVariable( $self, $http, 'set' );

    my @clusterCollect = ();
    my $clusterMember  = {};
    my $incldes        = getIncludeContents( $self, $http, 'server' );
    my $serverRs       = transObjRef( $self, $http->{'server'}, $incldes );

    my @serverCollect = ();
    for my $server (@$serverRs) {

        #扁平化处理
        my $ins = {};
        $ins->{_OBJ_CATEGORY}        = CollectObjCat->get('INS');
        $ins->{SERVER_NAME}          = 'nginx';
        $ins->{EXE_PATH}             = $exePath;
        $ins->{BIN_PATH}             = $binPath;
        $ins->{INSTALL_PATH}         = $basePath;
        $ins->{VERSION}              = $version;
        $ins->{PREFIX}               = $prefix;
        $ins->{CONFIG_PATH}          = $configPath;
        $ins->{WORKER_CONNECTIONS}   = $worker_connections;
        $ins->{WORKER_PROCESSES}     = $worker_processes;
        $ins->{DEFAULT_TYPE}         = $default_type;
        $ins->{CLIENT_MAX_BODY_SIZE} = $client_max_body_size;
        $ins->{SENDFILE}             = $sendfile;
        $ins->{TCP_NOPUSH}           = $tcp_nopush;
        $ins->{GZIP}                 = $gzip;
        $ins->{UPSTREAM}             = \@upstream;

        $ins->{'SERVICE_NAME'} = getStringValue( $self, $server, 'server_name' );
        my $listen = getStringValue( $self, $server, 'listen' );
        my $port;
        if ( $listen =~ /(\d+)/ ) {
            $port = $1;
        }

        $ins->{'SERVICE_PORT'} = $port;
        $ins->{PORT}           = $port;
        $ins->{MON_PORT}       = $port;
        $ins->{ADMIN_PORT}     = $port;

        my $type = 'http';
        if ( $listen =~ /ssl/ ) {
            $type = 'https';
        }
        $ins->{'SERVICE_TYPE'}      = $type;
        $ins->{'CHARSET'}           = getStringValue( $self, $server, 'charset' );
        $ins->{'KEEPALIVE_TIMEOUT'} = getStringValue( $self, $server, 'keepalive_timeout', '75' );
        my $serverVariable = getSetVariable( $self, $server, 'set', $variable );
        $ins->{'LOCATION'} = getLocation( $self, $server, 'location', $ins, $serverVariable );

        $ins->{'MEMBER_PEER'} = getMemberPeer( $self, $ins, @upstream, $serverVariable );
        push( @serverCollect, $ins );

        $clusterMember->{"$MGMT_IP:$port"} = $ins->{'MEMBER_PEER'};
    }

    #$nginxInfo->{SERVERS} = \@serverCollect;

    #实例集群
    while ( my ( $k, $v ) = each %$clusterMember ) {
        my $target         = $k;
        my $clusterMembers = $v;
        my $objCat         = CollectObjCat->get('CLUSTER');
        my $clusterInfo    = {
            _OBJ_CATEGORY => $objCat,
            _OBJ_TYPE     => 'NginxCluster',
            INDEX_FIELDS  => CollectObjCat->getIndexFields($objCat),
            MEMBERS       => []
        };

        $clusterInfo->{MGMT_IP}          = substr( $k, 0, index( $k, ':' ) );
        $clusterInfo->{PORT}             = substr( $k, index( $k, ':' ) + 1, length($k) );
        $clusterInfo->{UNIQUE_NAME}      = "Nginx:$target";
        $clusterInfo->{CLUSTER_MODE}     = 'Cluster';
        $clusterInfo->{CLUSTER_SOFTWARE} = 'Nginx';
        $clusterInfo->{CLUSTER_VERSION}  = $version;
        $clusterInfo->{NAME}             = "$target";
        $clusterInfo->{MEMBER_PEER}      = $clusterMembers;
        push( @clusterCollect, $clusterInfo );
    }

    return ( @serverCollect, @clusterCollect );
}

sub getIncludeFiles {
    my ( $self, $data, $key ) = @_;
    my $confPath = $self->{'configPath'};
    my @files    = ();
    if ( exists( $data->{$key} ) ) {
        my $includes = $data->{$key};
        for my $include (@$includes) {
            my $newValue;
            if ( ref($include) =~ /Array/ ) {
                for my $v (@$include) {
                    if ( $v !~ /mime.types/ and $v =~ /\.conf/ ) {
                        my $file;
                        if ( -f $v ) {
                            $file = $v;
                        }
                        else {
                            $file = File::Spec->catfile( $confPath, $v );
                        }
                        $file =~ s/;//;
                        push( @files, $file );
                    }
                }
            }
            else {
                if ( $include !~ /mime.types/ and $include =~ /\.conf/ ) {
                    my $file;
                    if ( -f $include ) {
                        $file = $include;
                    }
                    else {
                        $file = File::Spec->catfile( $confPath, $include );
                    }
                    $file =~ s/;//;
                    push( @files, $file );
                }
            }
        }
    }
    my @confFiles = ();
    foreach my $file (@files) {
        if ( $file =~ /\*/ ) {
            my @rexfiles = glob("$file");
            foreach my $conf (@rexfiles) {
                push( @confFiles, $conf );
            }
        }
        else {
            push( @confFiles, $file );
        }
    }
    return \@confFiles;
}

sub getIncludeContents {
    my ( $self, $data, $key ) = @_;
    my $files = getIncludeFiles( $self, $data, 'include' );
    if ( scalar(@$files) > 0 ) {
        my @insCollections = ();
        for my $file (@$files) {
            my $cfg     = Config::Neat->new();
            my $newdata = $cfg->parse_file($file);

            my $datacollects;
            if ( exists( $newdata->{'server'} ) ) {
                $datacollects = $newdata->{'server'};
            }
            elsif ( exists( $newdata->{'location'} ) ) {
                $datacollects = $newdata->{'location'};
            }
            if ( defined($datacollects) ) {
                if ( ref($datacollects) eq 'HASH' ) {
                    push( @insCollections, $newdata->{'server'} );
                }
                else {
                    for my $ins (@$datacollects) {
                        push( @insCollections, $ins );
                    }
                }
            }
        }
        return \@insCollections;
    }
    else {
        return undef;
    }
}

sub transObjRef {
    my ( $self, $target, $include ) = @_;
    my @list = ();
    if ( ref($target) eq 'HASH' ) {
        push( @list, $target );
    }
    else {
        @list = @$target;
    }

    if ( defined($include) ) {
        if ( ref($include) eq 'HASH' ) {
            push( @list, $include );
        }
        else {
            for my $inc (@$include) {
                push( @list, $inc );
            }
        }
    }
    return \@list;
}

sub getStringValue {
    my ( $self, $data, $key, $defaultValue ) = @_;
    my $newValue;
    if ( not defined($defaultValue) ) {
        $defaultValue = '';
    }
    if ( exists( $data->{$key} ) ) {
        my $value = $data->{$key};
        for my $v (@$value) {
            if ( $v ne ';' ) {
                $newValue = $newValue . ' ' . $v;
            }
        }
        $newValue =~ s/^\s+|\s+$//g;
        $newValue =~ s/;//;
    }
    else {
        $newValue = $defaultValue;
    }
    return $newValue;
}

#后续添加的相同变量，以最后添加顺序为准（如http、server内定义了相同变量，以server的作用域为准）
sub getSetVariable {
    my ( $self, $data, $key, $frontVariable ) = @_;
    my $variables = {};
    if ( not defined($frontVariable) ) {
        $variables = {};
    }
    else {
        $variables = $frontVariable;
    }
    if ( exists( $data->{$key} ) ) {
        my $value = $data->{$key};
        for my $ins (@$value) {
            if ( scalar(@$ins) > 1 ) {
                my $k = @$ins[0];
                my $v = @$ins[1];
                $k =~ s/^\s+|\s+$//g;
                $k =~ s/;//;
                $v =~ s/^\s+|\s+$//g;
                $v =~ s/;//;
                $variables->{$k} = $v;
            }
        }
    }
    return $variables;
}

sub getUpstream {
    my ( $self, $data, $key ) = @_;
    my @upstreamList = ();
    if ( exists( $data->{$key} ) ) {
        my $upsRs = transObjRef( $self, $data->{$key} );
        for my $ups (@$upsRs) {
            my $upstream = {};
            $upstream->{'NAME'} = getStringValue( $self, $ups, '' );
            my @upsList = ();
            my $srRs    = $ups->{'server'};
            for my $sr (@$srRs) {
                my $target = @$sr[0];
                if ( $target =~ /((\d{1,3}.){3}\d{1,3}:\d+)/ ) {
                    $target = $1;
                }
                push( @upsList, $target );
            }
            $upstream->{'TARGET'} = \@upsList;
            push( @upstreamList, $upstream );
        }
    }
    return \@upstreamList;
}

sub getLocation {
    my ( $self, $data, $key, $serverIns, $frontVariable ) = @_;
    my @lcList = ();
    if ( exists( $data->{$key} ) ) {
        my $incldes  = getIncludeContents( $self, $data, 'location' );
        my $location = transObjRef( $self, $data->{$key}, $incldes );
        for my $lc (@$location) {
            my $name = getStringValue( $self, $lc, '' );
            if ( $name =~ '50x' or $name =~ /status/ ) {
                next;
            }
            my $ins = {};
            $ins->{_OBJ_CATEGORY} = CollectObjCat->get('INS');
            $ins->{_OBJ_TYPE}     = 'NginxLocation';
            $ins->{'NAME'}        = getStringValue( $self, $lc, '' );
            my $status = 'off';
            if ( $ins =~ /status/ ) {
                $status = 'on';
            }
            $serverIns->{'SERVICE_STATUS'} = $status;

            #location自定义变量
            my $variables  = getSetVariable( $self, $lc, 'set', $frontVariable );
            my $proxy_pass = getStringValue( $self, $lc, 'proxy_pass' );
            if ( defined($proxy_pass) and $proxy_pass ne '' ) {
                $proxy_pass = getProxyPass( $self, $proxy_pass, $variables );
            }

            $ins->{'PROXY_PASS'} = $proxy_pass;
            $ins->{'ALIAS'}      = getStringValue( $self, $lc, 'alias' );
            $ins->{'ROOT'}       = getStringValue( $self, $lc, 'root' );
            push( @lcList, $ins );
        }
    }
    return \@lcList;
}

sub getMemberPeer {
    my ( $self, $httpIns, $upstream, $variables ) = @_;
    my @memberpeer = ();
    my $location   = $httpIns->{'LOCATION'};
    for my $lc (@$location) {
        my $isUps      = 0;
        my $proxy_pass = $lc->{'PROXY_PASS'};
        if ( not defined($proxy_pass) or $proxy_pass eq '' ) {
            next;
        }

        #upstream负载均衡变量
        for my $ups (@$upstream) {
            my $name = $ups->{'NAME'};
            if ( $proxy_pass =~ $name ) {
                $isUps = 1;
                my $target = $ups->{'TARGET'};
                for my $t (@$target) {
                    push( @memberpeer, $t );
                }
                last;
            }
        }

        #自定义变量处理
        if ( $isUps == 0 ) {
            $proxy_pass = getProxyPass( $self, $proxy_pass, $variables );
        }

        #静态文本
        if ( $isUps == 0 ) {
            $proxy_pass = getProxyPass( $self, $proxy_pass );
        }
        if ( defined($proxy_pass) ) {
            if ( $proxy_pass =~ /((\d{1,3}.){3}\d{1,3}:\d+)/ ) {
                push( @memberpeer, $1 );
            }
        }
    }

    my $valid      = {};
    my @newMempeer = ();
    for my $peer (@memberpeer) {
        if ( not defined( $valid->{$peer} ) ) {
            push( @newMempeer, $peer );
            $valid->{$peer} = 1;
        }
    }
    @memberpeer = undef;
    return \@newMempeer;
}

sub getProxyPass {
    my ( $self, $proxy_pass, $variables ) = @_;

    #变量替换
    if ( defined($variables) ) {
        while ( my ( $k, $v ) = each %$variables ) {
            if ( $proxy_pass =~ /\Q$k\E/ ) {
                $proxy_pass =~ s/\Q$k\E/$v/g;
            }
        }
    }

    #本机ip
    if ( $proxy_pass =~ /127.0.0.1/ or $proxy_pass =~ /localhost/ ) {
        my $mgmt_ip = $self->{procInfo}->{MGMT_IP};
        $proxy_pass =~ s/127.0.0.1/$mgmt_ip/g;
        $proxy_pass =~ s/localhost/$mgmt_ip/g;
    }

    return $proxy_pass;

}

1;
