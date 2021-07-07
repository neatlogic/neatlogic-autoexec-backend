#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package DemoCollector;
use parent 'BaseCollector';    #继承BASECollector

use File::Basename;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps  => ['\java\s'],               #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },        #ps的属性的精确匹配
        envAttrs => { TS_INSNAME => undef }    #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
sub collect {
    my ($self) = @_;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};

    #TODO：读取命令行输出或者读取配置文件，写入数据到hash map $appInfo

    #默认的APP_TYPE是类名去掉Collector，如果要特殊的名称则自行设置
    #$appInfo->{APP_TYPE} = 'DemoApp';
    return $appInfo;
}

1;
