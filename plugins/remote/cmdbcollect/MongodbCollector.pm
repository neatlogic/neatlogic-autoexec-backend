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
use CollectObjType;
use MongoDBExec;
use Data::Dumper;

sub getConfig {
    return {
        regExps => ['\b\/bin\/mongod\s'],         #正则表达是匹配ps输出
        psAttrs => { COMM => 'mongod' }    #ps的属性的精确匹配
    };
}

#采集数据对象的Primary Key设置，只需要在返回多种类型对象的收集器里定义
#注意：！！如果是返回单类型对象的采集器不需要定义此函数，可以删除此函数
sub getPK {
    my ($self) = @_;
    return {
        $self->{defaultAppType} => [ 'MGMT_IP', 'PORT', ]
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
    my $mongodbInfo        = {};
    $mongodbInfo->{OBJECT_TYPE} = $CollectObjType::DB;

    #设置此采集到的对象对象类型，可以是：CollectObjType::APP，CollectObjType::DB，CollectObjType::OS
    my $command    = $procInfo->{COMMAND};
    my $exePath    = $procInfo->{EXECUTABLE_FILE};
    my $binPath   = dirname($exePath);
    my $basePath   = dirname($binPath);
    my $configFile = File::Spec->catfile( $basePath, "mongodb.conf" );
    $mongodbInfo->{INSTALL_PATH} = $basePath;
    $mongodbInfo->{BIN_PATH}=$binPath ;
    $mongodbInfo->{CONFIG_FILE}  = $configFile;
    

    #配置文件
    parseConfig( $self, $configFile, $mongodbInfo );

    my $port = $mongodbInfo->{'PORT'};
    my $host = '127.0.0.1';

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
    $mongodbInfo->{VERSION} = $version ;    
    $mongodbInfo->{CHARACTERSET} = $procInfo->{'ENVRIONMENT'}->{'LANG'};

    my $mongodb = MongoDBExec->new(
        mongodbHome => $binPath,
        username  => $self->{defaultUsername},
        password  => $self->{defaultPassword},
        host      => $host,
        port      => $port
    );
    $self->{mongodb} = $mongodb;
    my ( $status, $rows ) = $mongodb->query(
        sql     => q(
		use admin;
		show dbs ;
		),
        verbose => $self->{isVerbose}
    );
    my @dbNames =();
    foreach my $line (@$rows){
        my @tmp_arr = str_split( $line, '\s+' );
        my $dbname = str_trim(@tmp_arr[0]);
        if( $dbname ne 'local' and $dbname ne 'config'  ){
	    my $db = {};
	    $db->{NAME} = $dbname ;    
	    push(@dbNames , $db);
        }
    }

   my ( $status, $rows ) = $mongodb->query(
        sql     => q(
                use admin;
                db.system.users.find({},{"user":1 , "db" :2}) ;
                ),
        verbose => $self->{isVerbose}
    );
    my %allUser = ();
    foreach my $line (@$rows){
	my $tmp = decode_json($line);
	my $user = $tmp->{'user'} ;
        my $db = $tmp->{'db'};
	my @users ;
        if(defined( $allUser{$db}) ){
	    @users = $user->{$db};
        }else{
	    @users = ();
	}
	push(@users , $user);
	$allUser{$db} = \@users;
    }
    
    my @newDbNames = ();
    foreach my $db (@dbNames){
	if( defined($allUser{$db->{NAME}}) ){
	    $db->{USERS} = $allUser{$db->{NAME}};
	}
	push(@newDbNames , $db);
    }
    $mongodbInfo->{DB_INS}= \@newDbNames ;

    $mongodbInfo->{CLUSTER_MODE} = undef;
    $mongodbInfo->{CLUSTER_ROLE} = undef;
    $mongodbInfo->{IS_CLUSTER}   = 0;
=pod
    if ( $mode eq 'cluster' ) {
        $mongodbInfo->{CLUSTER_MODE} = 'Master-Slave';
        $mongodbInfo->{CLUSTER_ROLE} = $role;
        $mongodbInfo->{IS_CLUSTER}   = 1;
        if ( $role eq 'slave' ) {
            $mongodbInfo->{MASTER_IPS} = $master_host . ":" . $master_port;
        }
        else {
            my $cns       = int( $info->{CONNECTED_SLAVES} );
            my @slave_arr = ();
            for ( $a = 0 ; $a < $cns ; $a = $a + 1 ) {
                my $slave = $info->{ 'SLAVE' . $a };
                $slave =~ s/'slave'$a//g;
                my @slave_tmp = str_split( $slave, ',' );
                my $slave_host;
                my $slave_port;
                foreach my $st (@slave_tmp) {
                    if ( $st =~ /ip/ig ) {
                        my @st_tmp = str_split( $st, '=' );
                        $slave_host = $st_tmp[1];
                    }
                    if ( $st =~ /port/ig ) {
                        my @st_tmp = str_split( $st, '=' );
                        $slave_port = $st_tmp[1];
                    }
                }
                push( @slave_arr, $slave_host . ":" . $slave_port );
            }
            $mongodbInfo->{SLAVE_IPS} = \@slave_arr;
        }
    }
=cut
    #服务名, 要根据实际来设置
    $mongodbInfo->{SERVER_NAME} = $procInfo->{APP_TYPE};
    return $mongodbInfo;
}

#配置文件
sub parseConfig {
    my ( $self, $configFile, $mongodbInfo ) = @_;
    my $configData = $self->getFileLines($configFile);

    #只取定义的配置
    my $filter = {
        "port"     => 1,
        "dbpath"        => 1,
        "logpath"       => 1,
        "fork"           => 1,
        "auth"    => 1,
        "logappend"     => 1,
        "bind_ip"     => 1,
        "nohttpinterface" => 1
    };
    foreach my $line (@$configData) {
        chomp($line);
        $line =~ s/^\s+//g;
        $line =~ ~s/\s+$//g;
        if ( $line =~ /^#/ or $line eq '' ) {
            next;
        }

        my @values = str_split( $line, '=' );
        if ( scalar(@values) > 1 ) {
            my $key   = str_trim( @values[0] );
            my $value = str_trim( @values[1] );
            $value =~ s/['"]//g;
            if ( defined( $filter->{$key} ) ) {
                $mongodbInfo->{ uc($key) } = $value;
            }
        }
    }
}

sub str_split {
    my ( $str, $separator ) = @_;
    my @values = split( /$separator/, $str );
    return @values;
}

sub str_trim {
    my ($str) = @_;
    $str =~ s/^\s+|\s+$//g;
    return $str;
}

1;
