#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package MongodbCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Socket;
use JSON;
use File::Spec;
use File::Basename;
use IO::File;
use File::Copy;
use Sys::Hostname;
use CollectObjCat;
use MongoDBExec;
use Data::Dumper;

sub getConfig {
    return {
        regExps => ['\b\/bin\/mongod\s'],    #正则表达是匹配ps输出
        psAttrs => { COMM => 'mongod' }      #ps的属性的精确匹配
    };
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
sub collect {
    my ($self) = @_;

    $self->{isVerbose} = 0;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    my $osUser           = $procInfo->{USER};
    my $mongodbInfo      = {};
    $mongodbInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DB');

    #服务名, 要根据实际来设置
    $mongodbInfo->{SERVER_NAME} = $procInfo->{_OBJ_TYPE};

    #设置此采集到的对象对象类型，可以是：CollectObjCat->get('INS')，CollectObjCat->get('DB')，CollectObjCat::OS
    my $configFile;
    my $command = $procInfo->{COMMAND};

    my $exePath = $procInfo->{EXECUTABLE_FILE};
    if ( $command =~ /^(.*?\/mongod)/ ) {
        if ( $exePath !~ /\// ) {
            $exePath = $1;
        }
    }

    my $binPath  = dirname($exePath);
    my $basePath = dirname($binPath);
    if ( $command =~ /\s(-f|--config)\s+(.*?)\s+-/ or $command =~ /\s(-f|--config)\s+(.*?)\s*$/ ) {
        $configFile = $2;
    }
    else {
        $configFile = File::Spec->catfile( $basePath, "mongodb.conf" );
    }

    $mongodbInfo->{INSTALL_PATH} = $basePath;
    $mongodbInfo->{BIN_PATH}     = $binPath;
    $mongodbInfo->{CONFIG_FILE}  = $configFile;

    #配置文件
    parseConfig( $self, $configFile, $mongodbInfo );

    my $port = $mongodbInfo->{PORT};
    if ( not defined($port) ) {
        my $minPort     = 65535;
        my $listenAddrs = $procInfo->{CONN_INFO}->{LISTEN};
        foreach my $lsnPort ( keys(%$listenAddrs) ) {
            if ( $lsnPort =~ /^(.*?):(\d+)$/ ) {
                $lsnPort = ($2);
            }
            if ( $lsnPort < $minPort ) {
                $minPort = $lsnPort;
            }
        }
        $port = $minPort;
    }
    $mongodbInfo->{PORT}           = $port;
    $mongodbInfo->{SSL_PORT}       = $port;
    $mongodbInfo->{MON_PORT}       = $port;
    $mongodbInfo->{ADMIN_PORT}     = $port;
    $mongodbInfo->{ADMIN_SSL_PORT} = $port;

    my $version = $self->getCmdOut("$exePath --version");
    $version =~ /\"version\": (\S+)\s+/;
    $version = $1;
    $version =~ s/,//g;
    $version =~ s/"//g;
    $mongodbInfo->{VERSION}      = $version;
    $mongodbInfo->{CHARACTERSET} = $procInfo->{'ENVIRONMENT'}->{'LANG'};

    my $host    = '127.0.0.1';
    my $mongodb = MongoDBExec->new(
        mongodbHome => $binPath,
        username    => $self->{defaultUsername},
        password    => $self->{defaultPassword},
        host        => $host,
        port        => $port
    );
    $self->{mongodb} = $mongodb;
    my ( $status, $rows ) = $mongodb->query(
        sql => q(
		use admin;
		show dbs ;
		),
        verbose => $self->{isVerbose}
    );
    my @dbNames = ();
    foreach my $line (@$rows) {
        my @tmp_arr = split( /\s+/, $line );
        my $dbname = $tmp_arr[0];
        $dbname =~ s/^\s*|\s*$//g;
        if ( $dbname ne 'local' and $dbname ne 'config' ) {
            my $db = {};
            $db->{NAME} = $dbname;
            push( @dbNames, $db );
        }
    }

    my ( $status, $rows ) = $mongodb->query(
        sql => q(
                use admin;
                db.system.users.find({},{"user":1 , "db" :2}) ;
                ),
        verbose => $self->{isVerbose}
    );

    my %allUser = ();
    if ( $status == 0 ) {
        foreach my $line (@$rows) {
            my $tmp  = from_json($line);
            my $user = $tmp->{'user'};
            my $db   = $tmp->{'db'};
            my @users;
            if ( defined( $allUser{$db} ) ) {
                @users = $user->{$db};
            }
            else {
                @users = ();
            }
            push( @users, $user );
            $allUser{$db} = \@users;
        }
    }

    my @newDbNames = ();
    foreach my $db (@dbNames) {
        if ( defined( $allUser{ $db->{NAME} } ) ) {
            $db->{USERS} = $allUser{ $db->{NAME} };
        }
        push( @newDbNames, $db );
    }
    $mongodbInfo->{DB_INS} = \@newDbNames;

    my ( $status, $rows ) = $mongodb->query(
        sql => q(
		use admin;
		print(rs.status().ok);
		),
        verbose     => $self->{isVerbose},
        parseOutput => 0
    );

    $rows =~ s/^\s*|\s*$//g;
    my $rsStatus = int($rows);
    if ( $rsStatus == 0 ) {    #单实例
        $mongodbInfo->{CLUSTER_MODE} = undef;
        $mongodbInfo->{CLUSTER_ROLE} = undef;
        $mongodbInfo->{IS_CLUSTER}   = 0;
    }
    else {
        my ( $status, $rows ) = $mongodb->query(
            sql => q(
            use admin;
            printjson(rs.status().members.map(function(m) { return {'name':m.name, 'stateStr':m.stateStr} }));
            ),
            verbose     => $self->{isVerbose},
            parseOutput => 0
        );
        my $members = from_json($rows);
        my $master_ips;
        my @slave_arr = ();
        foreach my $node (@$members) {
            my $name     = $node->{'name'};
            my $stateStr = $node->{'stateStr'};
            $mongodbInfo->{CLUSTER_MODE} = 'replSet';

            if ( $name eq "$host:$port" ) {
                $mongodbInfo->{CLUSTER_ROLE} = $stateStr;
            }
            if ( $stateStr == 'PRIMARY' && $name eq "$host:$port" ) {
                $mongodbInfo->{MASTER_IPS} = $name;
            }
            else {
                push( @slave_arr, $name );
            }
        }
        $mongodbInfo->{SLAVE_IPS} = \@slave_arr;
    }
    return $mongodbInfo;
}

#配置文件
sub parseConfig {
    my ( $self, $configFile, $mongodbInfo ) = @_;
    my $configData = $self->getFileLines($configFile);

    #只取定义的配置
    my $filter = {
        "port"            => 1,
        "dbpath"          => 1,
        "logpath"         => 1,
        "fork"            => 1,
        "auth"            => 1,
        "logappend"       => 1,
        "bind_ip"         => 1,
        "nohttpinterface" => 1
    };
    foreach my $line (@$configData) {
        $line =~ s/^\s*|\s*$//g;
        if ( $line =~ /^#/ or $line eq '' ) {
            next;
        }

        my @values = split( /=/, $line );
        if ( scalar(@values) > 1 ) {
            my $key   = $values[0];
            my $value = $values[1];
            $key =~ s/^\s+|\s+$//g;
            $value =~ s/^\s+['"]|['"]\s+$//g;
            if ( defined( $filter->{$key} ) ) {
                $mongodbInfo->{ uc($key) } = $value;
            }
        }
    }
}

1;

