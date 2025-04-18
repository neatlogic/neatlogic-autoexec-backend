#!/usr/bin/env perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package NacosCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

sub getConfig {
    return {
        regExps  => ['\bnacos-server.jar\b'],    #正则表达是匹配ps输出
        psAttrs  => { COMM => 'java' },                                           #ps的属性的精确匹配
        envAttrs => {}                                                            #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $envMap           = $procInfo->{ENVIRONMENT};
    my $matchedProcsInfo = $self->{matchedProcsInfo};
    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};
    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');
	$self->getJavaAttrs($appInfo);


    my ( $ports, $port ) = $self->getPortFromProcInfo($appInfo);

    if ( $port == 65535 ) {
        print("WARN: Can not determine Java listen port.\n");
    }
	
	
    if (grep { $_ == 8848 } @$ports) {
		$port = 8848;
	}
	
	$appInfo->{PORT} = $port;
	return $appInfo;
}

1;
