#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package DemoCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps  => ['\bjava\s'],                #正则表达是匹配ps输出
        psAttrs  => { COMM       => 'java' },    #ps的属性的精确匹配
        envAttrs => { TS_INSNAME => undef }      #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
#采集器实现需要重载这个类
#Return：如果判断当前进程不是想要的进程，返回undef，否则返回应用信息的HashMap
sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    my $user             = $procInfo->{USER};
    my $envMap           = $procInfo->{ENVIRONMENT};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    #设置此采集到的对象对象类型，可以是：CollectObjCat->get('INS')，CollectObjCat->get('DBINS')，CollectObjCat::OS

    #TODO：读取命令行输出或者读取配置文件，写入数据到hash map $appInfo

    #默认的_OBJ_TYPE是类名去掉Collector，如果要特殊的名称则自行设置
    #$appInfo->{_OBJ_TYPE} = 'DemoApp';

    #!!!如果是Java则采集Java的标准属性，否则删除这一行
    $self->getJavaAttrs($appInfo);

    #!!!下面的是标准属性，必须采集并转换提供出来
    #服务名, 要根据实际来设置
    $appInfo->{SERVER_NAME}    = $procInfo->{_OBJ_TYPE};
    $appInfo->{INSTALL_PATH}   = undef;
    $appInfo->{CONFIG_PATH}    = undef;
    $appInfo->{PORT}           = undef;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{SERVICE_PORTS}  = { tcp => 1521 };

    return $appInfo;

    #如果返回多个应用信息，则：return ($appInfo1, $appInfo2);
}

1;
