package collection_unix;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;
use File::Basename;
use Encode;
use Utils;

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();
    my %data = ();

    my $pro_num = `ps -ef | grep kafka/bin|grep -v collection_kafka |grep -v grep | head -n1 |awk '{print \$2}'`;
    if ( !$pro_num ) {
        print "not find kafka.\n";
        exit(0);
    }
    
    $data{'agentIP'} = $nodeIp;
    $data{'IP'}      = $nodeIp;
    $data{'部署于'}     = $nodeIp;
    my $host = `hostname`;
    chomp($host);
    $data{'名称'} = $host;

    my $type = 'kafka';
    $data{'中间件类型'} = $type;
    my $cwd = `ls -al /proc/$pro_num `;
    my $dir;
    if ( $cwd =~ /cwd\s+->\s+(\S+)/ ) {
        $dir = $1;
    }
    my $ver      = '';
    my $home_dir = dirname($dir);
    if ( -e "$home_dir" . '/libs' ) {
        chdir( $home_dir . '/libs' );
        my $lines = `ls`;
        if ( $lines =~ /kafka_(\d+\.\d+)-\S+\.jar/ ) {
            $ver = $1;
        }
    }
    $data{'版本'}   = $ver;
    $data{'安装路径'} = $home_dir;
    my $port = '9092';
    $data{'端口'} = $port;
    push(@collect_data , \%data);
    return @collect_data;
}

1;
