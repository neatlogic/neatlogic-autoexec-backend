#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package WebSphereMQCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;

sub getConfig {
    return {
        regExps  => ['\brunmqlsr\b'],                #正则表达是匹配ps输出
        psAttrs  => { COMM       => 'runmqlsr' },    #ps的属性的精确匹配
        envAttrs => { TS_INSNAME => undef }          #环境变量的正则表达式匹配，如果环境变量对应值为undef则变量存在即可
    };
}

#TODO：需要在实际环境进行测试，MQ的版本很多
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
    my $cmdLine          = $envMap->{COMMAND};

    my $appInfo = {};
    $appInfo->{_OBJ_CATEGORY} = CollectObjCat->get('INS');

    #$ ps -ef | grep runmqlsr
    #mqm      17411 17191  0 May04 ?        00:00:29 /opt/mqm/bin/runmqlsr -r -m QMGR1 -t TCP -p 1428
    my $homePath;
    if ( $cmdLine =~ /^(.*?)\/bin\/runmqlsr/ ) {
        $homePath = $1;
        $homePath =~ s/^["']|["']$//g;
    }
    my $mqmName;
    if ( $cmdLine =~ /-m\s+(\S+)/ ) {
        $mqmName = $1;
        $mqmName =~ s/^["']|["']$//g;
    }
    my $port;
    if ( $cmdLine =~ /-p\s+(\S+)/ ) {
        $port = $1;
        $port =~ s/^["']|["']$//g;
        $port = int($port);
    }

    my ( $status, $verInfo ) = $self->getCmdOut( 'dspmqver | grep Version', $user );
    my $version;
    if ( $verInfo =~ /Version\s+(\S+)/ ) {
        $version = $1;
    }
    if ( $status ne 0 ) {

        #not WebSphereMQ
        print("WARN: Process is not a WebSphereMQ process, $cmdLine.\n");
        return undef;
    }

    $appInfo->{INSTALL_PATH}   = $homePath;
    $appInfo->{CONFIG_PATH}    = $homePath;
    $appInfo->{SERVER_NAME}    = $mqmName;
    $appInfo->{PORT}           = $port;
    $appInfo->{SSL_PORT}       = undef;
    $appInfo->{ADMIN_PORT}     = undef;
    $appInfo->{ADMIN_SSL_PORT} = undef;

    my $ccsidInfo = $self->getCmdOut( "echo 'dis qmgr ccsid' | runmqsc $mqmName", $user );
    my $ccsid;
    if ( $ccsidInfo =~ /(?<=CCSID\()(\S+)(?=\))/ ) {
        $ccsid = $1;
    }
    $appInfo->{CCSID} = $ccsid;

    my @queues         = ();
    my $queueInfoLines = $self->getCmdOutLines( "echo 'dis q(*)' | runmqsc $mqmName", $user );
    foreach my $line (@$queueInfoLines) {
        if ( $line =~ /QUEUE\((\S+)\)\s+TYPE\((\S+)\)/ ) {
            my $queueInfo = {};
            $queueInfo->{NAME} = $1;
            $queueInfo->{TYPE} = $2;
            push( @queues, $queueInfo );
        }
    }
    $appInfo->{QUEUES} = \@queues;

    my @channels         = ();
    my $channelInfoLines = $self->getCmdOutLines( "echo 'dis chl(*)' | runmqsc $mqmName", $user );
    foreach my $line (@$channelInfoLines) {
        if ( $line =~ /CHANNEL\((\S+)\)\s+CHLTYPE\((\S+)\)/ ) {
            my $channelInfo = {};
            $channelInfo->{NAME} = $1;
            $channelInfo->{TYPE} = $2;
            push( @channels, $channelInfo );
        }
    }
    $appInfo->{CHANNELS} = \@channels;

    return $appInfo;
}

1;
