#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";

use strict;

package ActiveMQCollector;
use parent 'BaseCollector';    #继承BASECollector

use File::Basename;

sub getConfig {
    return {
        seq      => 100,
        regExps  => ['\ActiveMQ\s'],
        psAttrs  => {},
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
    my $appInfo  = {};

    my $cwd = $procInfo->{ENVRIONMENT}->{PWD};
    if ( -e "$cwd/activemq" ) {

        #应用的安装目录并非一定是当前目录，TODO：需要补充更好的方法，
        #譬如：如果命令行启动命令是绝对路径，直接可以作为安装的路径的计算
        my $output = `$cwd/activemq --version`;
        if ( $output =~ /ActiveMQ\s+(\d+\.\d+\.\d+)/ ) {
            my $version = $1;
            $appInfo->{VERSION} = $version;
        }

        my $installPath = dirname($cwd);
        $appInfo->{INSTALL_PATH} = $installPath;
        $appInfo->{SERVICE_NAME} = basename($installPath);

        my $port;
        my $confFile = "$installPath/conf/activemq.xml";
        if ( -e $confFile ) {
            my $fSize = -s $confFile;
            my $fh    = IO::File->new("<$confFile");
            if ( defined($fh) ) {
                my $xml;
                $fh->read( $xml, $fSize );

                #TODO: 需要确认activemq.xml文件中的监听配置
                my @ports = $xml =~ /static:\(nio:\/\/\d+\.\d+\.\d+\.\d+:(\d+)/g;
                $appInfo->{PORTS} = \@ports;
            }
        }
    }

    return $appInfo;
}

1;
