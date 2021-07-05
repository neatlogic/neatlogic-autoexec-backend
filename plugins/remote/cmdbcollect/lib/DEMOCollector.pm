#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib $FindBin::Bin;

package DEMOCollector;

use strict;
use parent 'BASECollector';

use File::Basename;

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

    return $appInfo;
}

1;
