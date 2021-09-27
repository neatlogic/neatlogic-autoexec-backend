#!/usr/bin/perl
#TODO: Tuxedo只是按照老的逻辑重写了一把，需要真实环境进行测试验证
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package TuxedoCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Cwd;
use File::Spec;
use File::Basename;
use IO::File;
use XML::MyXML qw(xml_to_object);
use CollectObjCat;

sub getConfig {
    return {
        regExps => ['\tuxedo\b']    #正则表达是匹配ps输出
                                    #psAttrs  => {},                  #ps的属性的精确匹配
                                    #envAttrs => {}                   #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

sub collect {
    my ($self) = @_;
    my $utils = $self->{collectUtils};

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo  = $self->{procInfo};
    my $envMap    = $procInfo->{ENVRIONMENT};
    my $listenMap = $procInfo->{CONN_INFO}->{LISTEN};

    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    my $pid     = $procInfo->{PID};
    my $cmdLine = $procInfo->{COMMAND};
    my $mgmtIp  = $procInfo->{MGMT_IP};

    my $user     = $procInfo->{USER};
    my $workPath = readlink("/proc/$pid/cwd");

    my $version;
    my ( $status, $verInfo ) = $self->getCmdOut( 'tmadmin -v', $user );

    if ( $status ne 0 ) {
        print("WARN: process $cmdLine is not a tuxedo process, because of execute tmadmin in user $user failed.\n");
        return;
    }

    if ( defined($verInfo) and $verInfo =~ /\d+(\.\d+)+/ ) {
        $version = $&;
    }
    $appInfo->{VERSION} = $version;

    my $insPath;
    my $insPathInfo = $self->getCmdOut( 'tmunloadcf |grep TUXDIR|head -n1', $user );
    if ( $insPathInfo =~ /[^=]+=\s*(.*?)\s*$/ ) {
        $insPath = $1;
        $insPath = substr( $insPath, 1, -2 );    #TODO：不确定为啥，没有环境
    }
    $appInfo->{INSTALL_PATH} = $insPath;

    my $domainId;
    my $domainIdInfo = $self->getCmdOut( q{tmunloadcf |grep -i domainid"|awk '{print $2}'}, $user );
    $domainIdInfo =~ s/^\s*|\s*$//g;
    $domainId = substr( $domainIdInfo, 1, -1 );
    $appInfo->{DOMAIN_ID} = $domainId;

    my @instances = ();

    my $confInfo = $self->getCmdOut( 'tmunloadcf', $user );
    my $serverInfo;
    if ( $confInfo =~ /\*SERVERS(.*)\*MODULES/s ) {
        $serverInfo = $1;
    }

    if ( defined($serverInfo) and $serverInfo ne '' ) {
        my @servers = $serverInfo =~ /"\S+"\s+.*?="\d+"(?=\n)?/sg;

        foreach my $server (@servers) {
            my $insInfo = {};
            $insInfo->{DOMAIN_ID} = $domainId;
            $insInfo->{IP}        = $mgmtIp;

            if ( $server =~ /SRVID=(\d+)/ ) {
                $insInfo->{ID} = $1;
            }
            if ( $server =~ /^"(\S+)"/ ) {
                $insInfo->{NAME} = $1;
            }
            if ( $server =~ /SRVGRP="(\S+)"/ ) {
                $insInfo->{GROUP} = $1;
            }
            if ( $server =~ /CLOPT/ and $server =~ /-s\s+(\S+)\s+/ ) {
                $insInfo->{PORT} = $1;
            }
            elsif ( $server =~ /CLOPT/ and $server =~ /-n\s+\/\/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\:(\d{1,5})/ ) {
                $insInfo->{PORT} = $1;
            }
            push( @instances, $insInfo );
        }
    }

    my $port;
    if ( scalar(@instances) > 0 ) {
        my $firstIns = $instances[0];
        $port = $firstIns->{PORT};
    }
    $appInfo->{PORT} = $port;

    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;
    $appInfo->{MON_PORT}       = $port;

    $appInfo->{SERVER_NAME} = $procInfo->{HOST_NAME};

    return $appInfo;
}
