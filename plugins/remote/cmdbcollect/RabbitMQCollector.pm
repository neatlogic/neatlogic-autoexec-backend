#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package RabbitMQCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

sub getConfig {
    return {
        regExps  => ['\brabbitmq\b'],    #正则表达是匹配ps输出
        #psAttrs  => { COMM => 'rabbitmq' },                                           #ps的属性的精确匹配
        #envAttrs => {}                                                            #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub getPK {
    my ($self) = @_;
    return {
        #默认KEY用类名去掉Collector，对应APP_TYPE属性值
        #配置值就是作为PK的属性名
        $self->{defaultAppType} => [ 'MGMT_IP', 'PORT' ]

            #如果返回的是多种对象，需要手写APP_TYPE对应的PK配置
    };
}

sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $envMap           = $procInfo->{ENVRIONMENT};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{OBJECT_TYPE} = $CollectObjType::APP;

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};

    my $homePath;
    my $version;
    my $port;

    if ( $cmdLine =~ /(?<=-pa\s)(\S+)/ ) {
        $homePath = dirname($1);
    }

    $appInfo->{INSTALL_PATH} = $homePath;

    chdir($homePath."/sbin");
    if ( -e 'rabbitmqctl' ) {
        my $ver_info = `./rabbitmqctl status|grep {rabbit,`;
        if ( $ver_info =~ /\d+\.\d+\.\d+/ ) {
            $version = $&;
        }
        my $port_info = `./rabbitmqctl status|grep listeners`;
        my @ports     = $port_info =~ /\d+/g;
        if ( @ports != 0 ) {
            $port = join( ',', @ports );
        }
    }


    $appInfo->{VERSION}      = $version;
    $appInfo->{SERVER_NAME}  = $procInfo->{HOST_NAME};

    $appInfo->{PORT}         = $port;
    #$appInfo->{MEMBERS}      = \@members;

    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $port;

    return $appInfo;
}
