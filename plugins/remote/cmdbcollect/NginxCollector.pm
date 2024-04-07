#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package NginxCollector;

#use parent 'BaseCollector';    #继承BaseCollector
use BaseCollector;
our @ISA = qw(BaseCollector);

use Socket;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use Config::Neat;

sub getConfig {
    return {
        seq      => 80,
        regExps  => ['\b(master|worker) process\s'],
        psAttrs  => { COMM => 'nginx' },
        envAttrs => {}
    };
}

sub init {
    my ($self) = @_;
    $self->{serverListenMap} = {};
}

sub getMasterProc {
    my ($self) = @_;

    my $procInfo;
    my $pFinder = $self->{pFinder};

    my $pid;
    my $masterPsLines = $self->getCmdOutLines('ps -eo pid,args |grep nginx |grep master');
    foreach my $line (@$masterPsLines) {
        if ( $line !~ /grep/ and $line =~ /^\s*(\d+)/ ) {
            $pid = $1;
            last;
        }
    }
    if ( defined($pid) ) {
        $procInfo = $pFinder->getProcess($pid);
    }

    return $procInfo;
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo = $self->{procInfo};
    if ( $procInfo->{PPID} != 1 ) {
        return undef;
    }

    my $command = $procInfo->{COMMAND};
    my $exePath = $procInfo->{EXECUTABLE_FILE};

    #子进程取父进程的cmd
    my $masterProcInfo = $self->getMasterProc();
    if ( defined($masterProcInfo) ) {
        $self->{procInfo}->{COMMAND} = $masterProcInfo->{COMMAND};
        $command = $masterProcInfo->{COMMAND};
    }

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

    #nginx子进程读取配置文件目录，子进程读取不到配置就读取父进程的配置，如读取不到直接return
    if ( !-e $configFile ) {
        if ( defined($masterProcInfo) ) {
            my $pprocInfo = $masterProcInfo->{procInfo};
            my $pcommand  = $pprocInfo->{COMMAND};
            my $ppid      = $pprocInfo->{PID};
            my $pworkPath = readlink("/proc/$ppid/cwd");

            if ( $pcommand =~ /\s-c\s+(.*?)\s+-/ or $pcommand =~ /\s-c\s+(.*?)\s*$/ ) {
                $configFile = $1;
                if ( $configFile !~ /^\// ) {
                    $configFile = "$pworkPath/$configFile";
                }
                $configPath = dirname($configFile);
            }
            if ( !-e $configFile ) {
                return undef;
            }
        }
        else {
            return undef;
        }
    }

    $self->{'configPath'} = $configPath;
    $self->{'configFile'} = $configFile;

    my $cfg       = Config::Neat->new();
    my $data      = $cfg->parse_file_with_include( $configFile, 1 );
    my $mainBlock = $self->getConfigMap($data);

    my $nginxInfo = $self->getNginxInsInfo($mainBlock);
    $nginxInfo->{EXE_PATH}     = $exePath;
    $nginxInfo->{BIN_PATH}     = $binPath;
    $nginxInfo->{INSTALL_PATH} = $basePath;
    $nginxInfo->{VERSION}      = $version;
    if ( $version =~ /(\d+)/ ) {
        $nginxInfo->{MAJOR_VERSION} = "Nginx$1";
    }

    $nginxInfo->{PREFIX}      = $prefix;
    $nginxInfo->{CONFIG_PATH} = $configPath;

    my @serverInfos     = ();
    my $httpServerInfos = $self->getHttpServers($mainBlock);
    $nginxInfo->{HTTP_SERVERS} = $httpServerInfos;
    my $streamServerInfos = $self->getStreamServers($mainBlock);
    $nginxInfo->{STREAM_SERVERS} = $streamServerInfos;

    push( @serverInfos, @$httpServerInfos );
    push( @serverInfos, @$streamServerInfos );

    return ( $nginxInfo, @serverInfos );
}

sub resolveVariable {
    my ( $self, $value, $variableMap ) = @_;
    foreach my $varName ( keys(%$variableMap) ) {
        my $varValue = $variableMap->{$varName};
        $value =~ s/\Q$varName\E/$varValue/g;
    }
    return $value;
}

sub getConfigMap {
    my ( $self, $confData, $variableMap, $upstreamMap ) = @_;

    #把nginx的配置，包含include的配置内容，转换为map格式
    #对于这几个指令进行把多个配置转换成map的处理：upstream、set、server
    #upstream.map：配置名作为key
    #set.map: 变量名作为key，变量名带符号'$'，例如：$my_var
    #server.map: 每个server_name作为key
    #set variable 的作用域处理
    #如过存在配置值引用了variable，同时根据作用域进行resolve
    my $myVariableMap = {};

    #把上层的variable map复制下来
    if ( defined($variableMap) ) {
        map { $myVariableMap->{$_} = $variableMap->{$_} } ( keys(%$variableMap) );
    }

    my $myUpstreamMap = {};
    if ( defined($variableMap) ) {
        map { $myUpstreamMap->{$_} = $upstreamMap->{$_} } ( keys(%$upstreamMap) );
    }

    my $mainBlock = {};
    while ( my ( $confKey, $confVal ) = each(%$confData) ) {
        my $valType = ref($confVal);
        if ( $valType =~ /HASH/ ) {
            $mainBlock->{$confKey} = $self->getConfigMap( $confVal, $myVariableMap );
            if ( $confKey eq 'server' ) {
                my $serverMap   = {};
                my $serverNames = $confVal->{'server_name'};
                if ( not defined($serverNames) ) {
                    $serverNames = [''];
                }
                foreach my $itemKey (@$serverNames) {
                    if ( defined($itemKey) ) {
                        if ( not defined( $serverMap->{$itemKey} ) ) {

                            #server的配置应该先配置优先
                            $serverMap->{$itemKey} = $self->getConfigMap( $confVal, $myVariableMap );
                        }
                    }
                }
                $mainBlock->{"server.map"} = $serverMap;
            }
            else {
                my $itemKey = $confVal->{''};
                my $itemMap = {};
                if ( defined($itemKey) ) {
                    $itemKey                     = $itemKey->as_string();
                    $itemMap->{$itemKey}         = $self->getConfigMap( $confVal, $myVariableMap );
                    $mainBlock->{"$confKey.map"} = $itemMap;
                }
            }
        }
        elsif ( $valType =~ /Array/ ) {
            my $firstItemType = ref( $$confVal[0] );
            my $itemsCount    = scalar(@$confVal);
            my $lastVal       = $$confVal[-1];

            if ( $firstItemType eq '' ) {

                #值数组元素是简单字串的情况
                my @simpleValues = ();
                if ( $itemsCount == 0 ) {
                    $mainBlock->{$confKey} = '';
                }
                elsif ( $itemsCount == 1 ) {

                    #如果只有一个值，则把值转为字符串
                    my $subVal = $confVal->as_string();
                    $mainBlock->{$confKey} = $self->resolveVariable( $subVal, $myVariableMap );
                }
                elsif ( $confKey eq 'set' ) {

                    #如果是set指令，建立一个新的块set.map, key是set的变量名，譬如：$my_var
                    my $setMap = $mainBlock->{'set.map'};
                    if ( not defined($setMap) ) {
                        $setMap = {};
                        $mainBlock->{'set.map'} = $setMap;
                    }
                    my $subVal = $$confVal[1];
                    $setMap->{ $$confVal[0] }        = $subVal;
                    $myVariableMap->{ $$confVal[0] } = $subVal;
                }
                else {
                    #其他设置为字符串数组
                    foreach my $subVal (@$confVal) {
                        $subVal = $self->resolveVariable( $subVal, $myVariableMap );
                        push( @simpleValues, $subVal );
                    }
                    $mainBlock->{$confKey} = \@simpleValues;
                }
            }
            elsif ( $firstItemType =~ /Array/ ) {

                #值数组元素还是数组
                my @itemValues = ();
                foreach my $subVal (@$confVal) {
                    $subVal = $self->resolveVariable( $subVal->as_string(), $myVariableMap );
                    push( @itemValues, $subVal );
                }
                $mainBlock->{$confKey} = \@itemValues;
            }
            elsif ( $firstItemType =~ /HASH/ ) {

                #值数组元素是配置块
                my @embededBlockConfs = ();
                my $embededBlockMap   = {};
                foreach my $item (@$confVal) {
                    my $itemKey = $item->{''};
                    if ( $confKey eq 'server' ) {

                        #server块的标记名是server_name
                        my $serverNames = $item->{'server_name'};
                        foreach $itemKey (@$serverNames) {
                            if ( defined($itemKey) ) {
                                if ( not defined( $embededBlockMap->{$itemKey} ) ) {

                                    #server的配置应该先配置优先
                                    $embededBlockMap->{$itemKey} = $self->getConfigMap( $item, $myVariableMap );
                                }
                            }
                            push( @embededBlockConfs, $self->getConfigMap($item), $myVariableMap );
                        }
                    }
                    else {
                        if ( defined($itemKey) ) {
                            $embededBlockMap->{ $itemKey->as_string() } = $self->getConfigMap( $item, $myVariableMap );
                        }
                        push( @embededBlockConfs, $self->getConfigMap( $item, $myVariableMap ) );
                    }
                }
                $mainBlock->{$confKey} = \@embededBlockConfs;
                $mainBlock->{"$confKey.map"} = $embededBlockMap;
            }
            else {
                print("WARN: Unexpected data type:$$firstItemType of config item $confKey.\n");
            }
        }
    }
    return $mainBlock;
}

sub getBlockSettingMap4Name {
    my ( $self, $mainBlock, $blockConfMap, $confName ) = @_;

    my $mainSettingMap = $mainBlock->{"$confName.map"};
    if ( not defined($mainSettingMap) ) {
        $mainSettingMap = {};
    }
    my $blockSettingMap = $blockConfMap->{"$confName.map"};
    if ( not defined($blockSettingMap) ) {
        $blockSettingMap = {};
    }

    #把主配置中的upstream合并到server层的upstream map中
    map { $blockSettingMap->{$_} = $mainSettingMap->{$_} } ( keys(%$mainSettingMap) );

    return $blockSettingMap;
}

sub getProxyPassMembers {
    my ( $self, $proxyPassVal, $upstreamsMap, $serverListenPorts ) = @_;

    #serverListenPorts: server监听的所有端口，对于upstream里的成员server没有配置端口的情况，则使用server listen的端口作为成员端口
    #如server listen多个端口，则变为多个server成员
    my @members = ();
    my $matched = 0;
    foreach my $upstreamName ( keys(%$upstreamsMap) ) {
        if ( $proxyPassVal =~ /\b$upstreamName\b/ ) {

            #如果匹配upstream的名称，则从upstream中找server member
            $matched = 1;
            my $upstreamServersList = $upstreamsMap->{$upstreamName}->{server};

            # if(ref($upstreamServersList) ne 'ARRAY'){
            #   #如果只有一个server，返回不是数组，转换成数组
            #   $upstreamServersList = [$upstreamServersList];
            # }

            foreach my $serverAddr (@$upstreamServersList) {
                $serverAddr =~ s/\s+.*$//g;
                my ( $host, $port ) = split( ':', $serverAddr, 2 );
                my $ipAddr = gethostbyname($host);
                if ( defined($ipAddr) ) {
                    $host = inet_ntoa($ipAddr);
                    if ( $host eq '127.0.0.1' ) {
                        $host = $self->{VIP};
                    }
                    if ( not defined($port) ) {
                        foreach my $listenPort (@$serverListenPorts) {
                            push( @members, "$host:$listenPort" );
                        }
                    }
                    else {
                        push( @members, "$host:$port" );
                    }
                }
            }
        }
    }

    if ( $matched == 0 ) {

        #如果不匹配upstream的名称，则从proxy_pass本身抽取server member
        if ( $proxyPassVal =~ /:\/\/([^\/]+)/ ) {

            #对于http的情况（在http块中）
            my $backendAddr = $1;
            my ( $host, $port ) = split( ':', $backendAddr, 2 );
            my $ipAddr = gethostbyname($host);
            if ( defined($ipAddr) ) {
                $host = inet_ntoa($ipAddr);
                if ( $host eq '127.0.0.1' ) {
                    $host = $self->{VIP};
                }
                push( @members, "$host:$port" );
            }
        }
        elsif ( $proxyPassVal =~ /^[\w\-\.]+$/ ) {

            #非http的情况（在stream块中）
            my $backendAddr = $proxyPassVal;
            my ( $host, $port ) = split( ':', $backendAddr, 2 );
            my $ipAddr = gethostbyname($host);
            if ( defined($ipAddr) ) {
                $host = inet_ntoa($ipAddr);
                if ( $host eq '127.0.0.1' ) {
                    $host = $self->{VIP};
                }
                push( @members, "$host:$port" );
            }
        }
        else {
            print("WARN: Can not parse proxy_pass config:$proxyPassVal.\n");
        }
    }

    return \@members;
}

sub hasListened {
    my ( $self, $serverName, $listenIp, $listenPort ) = @_;

    #因为nginx的server通过listen和server_name配置来实现virtual server
    #所以可能存在重复配置的可能，如果同一个server_name，监听不同的端口则当成两个server
    my $serverListenMap = $self->{serverListenMap};
    my $listenedMap     = $serverListenMap->{$serverName};
    if ( not defined($listenedMap) ) {
        $listenedMap = {};
        $serverListenMap->{$serverName} = $listenedMap;
    }

    my $listened = 0;

    if ( defined( $listenedMap->{0} ) ) {
        $listened = 1;
    }
    elsif ( defined( $listenedMap->{"*:$listenPort"} ) or defined( $listenedMap->{"0.0.0.0:$listenPort"} ) ) {
        $listened = 1;
    }
    elsif ( defined( $listenedMap->{"$listenIp:0"} ) ) {
        $listened = 1;
    }
    elsif ( defined( $listenedMap->{"$listenIp:$listenPort"} ) ) {
        $listened = 1;
    }

    $listenedMap->{"$listenIp:$listenPort"} = 1;
    return $listened;
}

sub getServerListenPorts {
    my ( $self, $serverName, $mainBlock, $serverBlock ) = @_;

    #mainBlock:主配置块
    #serverBlock：server配置块
    #liistenedMap：其他server已经listen的地址

    my @listenPorts = ();
    my @listenAddrs = ();
    my $listenConfs = $serverBlock->{listen};
    if ( not defined($listenConfs) ) {
        $listenConfs = $mainBlock->{listen};
    }

    if ( not defined($listenConfs) ) {
        $listenConfs = [];
    }
    elsif ( ref($listenConfs) ne 'ARRAY' ) {
        $listenConfs = [$listenConfs];
    }

    my @listenConfAddrs = ();
    foreach my $listenConf (@$listenConfs) {
        if ( ref($listenConf) eq 'ARRAY' ) {
            push( @listenConfAddrs, @$listenConf );
        }
        else {
            push( @listenConfAddrs, $listenConf );
        }
    }

    foreach my $listenAddr (@listenConfAddrs) {
        if ( $listenAddr =~ /((\S*):)?(\d*)/g ) {
            my $listenIp = $2 || '';
            if ( $listenIp eq 'localhost' ) {
                $listenIp = '127.0.0.1';
            }
            my $listenPort = int($3);

            if ( $listenPort == 0 ) {

                #TODO: 需要再确认一下liisten是否可以配置域名
                if ( $listenAddr =~ /^\w+$/ ) {
                    next;
                }
            }

            if ( $self->hasListened( $serverName, $listenIp, $listenPort ) ) {

                #如果在其他Server被监听过，则忽略
                next;
            }

            push( @listenPorts, $listenPort );

            if ( $listenIp ne '' ) {
                push( @listenAddrs, "$listenIp:$listenPort" );
            }
            else {
                push( @listenAddrs, $listenPort );
            }
        }
    }

    my @sortedListenPorts  = sort(@listenPorts);
    my @sortedListetnAddrs = sort(@listenAddrs);

    return \@sortedListenPorts;
}

sub getPrimaryIpAndPort {
    my ( $self, $serverName, $listenPorts ) = @_;

    my $serverListenMap = $self->{serverListenMap};
    my $listenedMap     = $serverListenMap->{$serverName};

    my $pFinder  = $self->{pFinder};
    my $procInfo = $self->{procInfo};
    my $connInfo = $procInfo->{CONN_INFO};

    my $isListenAllIp    = 0;
    my @explictListenIps = ();
    my $port             = $$listenPorts[0];
    foreach my $listenAddr ( keys(%$listenedMap) ) {
        if ( $listenAddr =~ /(\S+):\d+/ ) {
            my $explictListenIp = $1;
            if ( $explictListenIp ne '*' and $explictListenIp ne '0.0.0.0' ) {
                push( @explictListenIps, $1 );
            }
            else {
                $isListenAllIp = 1;
            }
        }
    }

    my $vip;
    if ( $isListenAllIp == 0 ) {
        my @possibleVips = ();
        if (@explictListenIps) {
            @possibleVips = sort(@explictListenIps);
            foreach my $possibleVip (@possibleVips) {
                foreach my $listenAddr ( keys(%$listenedMap) ) {
                    if ( $listenAddr =~ /$possibleVip:$port/ ) {
                        $vip = $possibleVip;
                        last;
                    }
                }
                if ( defined($vip) ) {
                    last;
                }
            }
        }
    }

    if ( not defined($vip) ) {
        $vip = $pFinder->predictBizIp( $connInfo, $port );
    }

    return $vip;
}

sub getValueWithInherit {
    my $self       = shift(@_);
    my $confName   = shift(@_);
    my @confBlocks = (@_);

    my $confVal;
    foreach my $confBlock (@confBlocks) {
        my $confVal = $confBlock->{$confName};
        if ( defined($confVal) ) {
            last;
        }
    }

    return $confVal;
}

sub getHttpServers {
    my ( $self, $mainBlock ) = @_;
    my @serverInfos = ();

    my $httpBlock = $mainBlock->{http};
    if ( not defined($httpBlock) ) {
        return \@serverInfos;
    }

    my $serversMap = $httpBlock->{'server.map'};
    if ( not defined($serversMap) ) {
        return \@serverInfos;
    }

    my $upstreamsMap = $self->getBlockSettingMap4Name( $mainBlock, $httpBlock, 'upstream' );
    $httpBlock->{'upstream.map'} = $upstreamsMap;

    my $serverList = $httpBlock->{server};
    foreach my $serverBlock (@$serverList) {
        my @serverNames = split( /\s+/, $serverBlock->{server_name} );
        foreach my $serverName (@serverNames) {
            my $myListenPorts = $self->getServerListenPorts( $serverName, $mainBlock, $serverBlock );

            if ( not @$myListenPorts ) {
                next;
            }

            my $upstreamsMap = $self->getBlockSettingMap4Name( $httpBlock, $serverBlock, 'upstream' );
            my $locationsMap = $self->getBlockSettingMap4Name( $httpBlock, $serverBlock, 'location' );

            my $listen     = $serverBlock->{listen} || '';
            my $serverType = 'http';
            if ( $listen =~ /ssl/i ) {
                $serverType = 'https';
            }

            my ( $vip, $port ) = $self->getPrimaryIpAndPort( $serverName, $myListenPorts );

            my @serverMembers = ();
            my @locationInfos = ();
            my $serverInfo    = {
                _OBJ_CATEGORY     => 'CLUSTER',
                _OBJ_TYPE         => 'Nginx-Server',
                APP_TYPE          => 'HTTP',
                NAME              => $serverName,
                UNIQUE_NAME       => "$serverName-$vip;$port",
                VIP               => $vip,
                PRIMARY_IP        => $vip,
                PORT              => $port,
                SERVICE_PORTS     => $myListenPorts,
                SERVER_TYPE       => $serverType,
                CHARSET           => $self->getValueWithInherit( 'charset',           $serverBlock, $httpBlock, $mainBlock ),
                KEEPALIVE_TIMEOUT => $self->getValueWithInherit( 'keepalive_timeout', $serverBlock, $httpBlock, $mainBlock ),
                MEMBER_PEER       => \@serverMembers,
                ACCESS_LOG        => $self->getValueWithInherit( 'access_log', $serverBlock, $httpBlock, $mainBlock ),
                ERROR_LOG         => $self->getValueWithInherit( 'error_log',  $serverBlock, $httpBlock, $mainBlock ),
                LOCATIONS         => \@locationInfos
            };
            while ( my ( $uri, $locationBlock ) = each(%$locationsMap) ) {
                my $proxyPassVal     = $locationBlock->{proxy_pass};
                my $proxyPassMembers = [];
                if ( defined($proxyPassVal) ) {
                    $proxyPassMembers = $self->getProxyPassMembers( $proxyPassVal, $upstreamsMap, $myListenPorts );
                    push( @serverMembers, @$proxyPassMembers );
                }
                push(
                    @locationInfos,
                    {
                        _OBJ_CATEGORY => 'INS',
                        _OBJ_TYPE     => 'Nginx-Http-Location',
                        NAME          => $uri,
                        PROXY_PASS    => $proxyPassVal,
                        MEMBER_PEER   => $proxyPassMembers
                    }
                );
            }

            push( @serverInfos, $serverInfo );
        }
    }

    return \@serverInfos;
}

sub getStreamServers {
    my ( $self, $mainBlock ) = @_;

    my @serverInfos = ();

    my $streamBlock = $mainBlock->{stream};
    if ( not defined($streamBlock) ) {
        return \@serverInfos;
    }

    my $serversMap = $streamBlock->{'server.map'};
    if ( not defined($serversMap) ) {
        return \@serverInfos;
    }

    my $upstreamsMap = $self->getBlockSettingMap4Name( $mainBlock, $streamBlock, 'upstream' );
    $streamBlock->{'upstream.map'} = $upstreamsMap;

    my $pFinder  = $self->{pFinder};
    my $procInfo = $self->{procInfo};
    my $connInfo = $procInfo->{CONN_INFO};

    while ( my ( $serverName, $serverBlock ) = each(%$serversMap) ) {
        my $myListenPorts = $self->getServerListenPorts( $serverName, $mainBlock, $serverBlock );
        my $upstreamsMap  = $self->getBlockSettingMap4Name( $streamBlock, $serverBlock, 'upstream' );
        my @serverMembers = ();

        my ( $vip, $port ) = $self->getPrimaryIpAndPort( $serverName, $myListenPorts );

        my $serverInfo = {
            _OBJ_CATEGORY => 'CLUSTER',
            _OBJ_TYPE     => 'Nginx-Stream',
            APP_TYPE      => 'Stream',
            NAME          => $serverName,
            UNIQUE_NAME   => "$serverName-$vip;$port",
            VIP           => $vip,
            PRIMARY_IP    => $vip,
            PORT          => $port,
            SERVER_TYPE   => 'stream',
            MEMBER_PEER   => \@serverMembers
        };

        my $proxyPassVal = $serverBlock->{proxy_pass};
        if ( defined($proxyPassVal) ) {
            my $proxyPassMembers = $self->getProxyPassMembers( $proxyPassVal, $upstreamsMap, $myListenPorts );
            push( @serverMembers, @$proxyPassMembers );
        }

        push( @serverInfos, $serverInfo );
    }

    return \@serverInfos;
}

sub getNginxInsInfo {
    my ( $self, $mainBlock ) = @_;

    my $nginxInfo = {
        DEFAULT_TYPE         => $mainBlock->{default_type},
        CLIENT_MAX_BODY_SIZE => $mainBlock->{client_max_body_size} || '1M',
        SENDFILE             => $mainBlock->{sendfile}             || 'on',
        TCP_NOPUSH           => $mainBlock->{tcp_nopush}           || 'off',
        GZIP                 => $mainBlock->{gzip}                 || 'off',
        WORKER_PROCESSES     => int( $mainBlock->{worker_processes}     || 1 ),
        WORKER_CONNECTIONS   => int( $mainBlock->{worker_connections}   || 1024 ),
        CLIENT_MAX_BODY_SIZE => int( $mainBlock->{client_max_body_size} || '1M' )
    };

    return $nginxInfo;
}

1;
