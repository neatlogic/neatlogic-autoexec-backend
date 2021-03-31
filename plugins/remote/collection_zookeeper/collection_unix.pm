package collection_unix;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use warnings;
use utf8;
use File::Basename;
use Encode;
use Utils;

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();
    my %data = ();

    my $pro_num = `ps -ef |grep org.apache.zookeeper.server.quorum.QuorumPeerMain|grep -v grep|head -n1|awk '{print \$2}'`;
    if ( !$pro_num ) {
        print "not find zookeeper process.\n";
        return @collect_data;
        exit(0);
    }

    $data{'IP'}      = $nodeIp;
    $data{'agentIP'} = $nodeIp;
    $data{'部署于'}     = $nodeIp;
    my $host = `hostname`;
    chomp($host);
    $data{'名称'} = $host;

    my $type = 'zookeeper';
    $data{'中间件类型'} = $type;

    my $pro_info = `ps -ef |grep org.apache.zookeeper.server.quorum.QuorumPeerMain|grep -v grep|head -n1`;
    my $home_dir;
    if ( $pro_info =~ /(?<=QuorumPeerMain\s)\S+zookeeper.*?\// ) {
        $home_dir = $&;
        print $&;
    }

    chdir($home_dir);
    my $ver;
    my $lines = `ls`;
    if ( $lines =~ /zookeeper-(\S+)\.jar/ ) {
        $ver = $1;
        $data{'版本'} = $ver;

        $data{'安装路径'} = $home_dir;
    }
    elsif ( -e $home_dir . '/install' ) {
        chdir( $home_dir . '/install' );
        my $ver;
        my $lines = `ls`;
        if ( $lines =~ /zookeeper-(\S+)\.jar/ ) {
            $ver = $1;
            $data{'版本'} = $ver;

            $data{'安装路径'} = $home_dir;
        }
    }
    else {
        $data{'安装路径'} = '/usr/lib/zookeeper';
        chdir('/usr/lib/zookeeper');
        my $lines = `ls`;
        if ( $lines =~ /zookeeper-(\S+)\.jar/ ) {
            $ver = $1;
            $data{'版本'} = $ver;
        }
    }

    my $port = '2181';
    $data{'端口'} = $port;
    push(@collect_data , \%data);

    return @collect_data;
}

1;
