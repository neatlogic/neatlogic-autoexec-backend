#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package InformixCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjType;

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps => ['\boninit\b'],                       #正则表达是匹配ps输出
        psAttrs => { PPID => '1', COMM => 'oninit' },    #ps的属性的精确匹配
        envAttrs => { INFORMIXDIR => undef }             #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
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

    my @collectSet = ();
    my $objType    = $CollectObjType::DB;

    my $homePath = $envMap->{INFORMIXDIR};
    my $confPath = "$homePath/etc";

    my $version;
    my $verInfo = $self->getCmdOut( 'onstat -', $user );
    if ( $verInfo =~ /Version\s+(\S+)\s/ ) {
        $version = $1;
    }

    # #ol_informix1210 onsoctcp sit_deploy_24 13668
    # ol_informix1210 onsoctcp 192.168.0.24  13668
    # dr_informix1210 drsoctcp sit_deploy_24 11585
    # lo_informix1210 onsoctcp 127.0.0.1 20686
    my $insInfoLines = $self->getFileContent("$homePath/etc/sqlhosts");
    foreach my $line (@$insInfoLines) {
        if ( $line =~ /^\s*#/ ) {
            next;
        }
        $line =~ s/^\s*|\s*$//g;
        my @insSegs = split( /\s+/, $line );
        if ( $insSegs[2] ne '127.0.0.1' and $insSegs[2] ne 'localhost' ) {
            my $insName = $insSegs[0];

            my $insInfo = {
                OBJECT_TYPE  => $objType,
                SERVER_NAME  => $insName,
                INSTALL_PATH => $homePath,
                CONF_PATH    => $confPath,
                VERSION      => $version
            };

            $insInfo->{NAME} = $insName;
            if ( $insSegs[2] =~ /\d+(\.\d+){3}/ ) {
                $insInfo->{IP} = $insSegs[2];
            }
            else {
                my $ipAddr = gethostbyname( $insSegs[2] );
                $insInfo->{IP} = inet_ntoa($ipAddr);
            }
            $insInfo->{PORT}     = $insSegs[3];
            $insInfo->{SSL_PORT} = undef;

            my $dbNameInfo = $self->getCmdOut( "echo 'select * from sysdatabases'|dbaccess -e sysmaster\@$insName", $user );
            my @dbNames    = ();
            my @users      = ();
            while ( $dbNameInfo =~ /name\s+(\S+)/sg ) {
                my $dbName = $1;
                push( @dbNames, { NAME => $dbName } );

                my $userInfo = $self->getCmdOut( "echo 'select * from sysusers'|dbaccess $dbName\@$insName", $user );
                while ( $userInfo =~ /username\s+(\S+)/g ) {
                    my $user = $1;
                    push( @users, { NAME => $user } );
                }
            }
            $insInfo->{DATABASES} = \@dbNames;
            $insInfo->{USERS}     = \@users;
            push( @collectSet, $insInfo );
        }
    }

    return @collectSet;
}

1;
