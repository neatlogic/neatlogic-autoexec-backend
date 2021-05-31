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
    my ($nodeIp)     = @_;
    my @collect_data = ();
    my %data         = ();

    my $pro_num = `ps -ef | grep -i ActiveMQ|grep -v collection_activemq |grep -v grep|head -n1|awk '{print \$2}'`;
    if ( !$pro_num ) {
        print "not find activeMQ process. \n";
        return @collect_data;
        exit(0);
    }

    $data{'IP'}      = $nodeIp;
    $data{'agentIP'} = $nodeIp;
    $data{'部署于'}     = $nodeIp;
    my $host = `hostname`;
    chomp($host);
    $data{'名称'} = $host;

    my $type = 'activemq';
    $data{'中间件类型'} = $type;

    my $cwd = `ls -al /proc/$pro_num `;
    my $dir;
    if ( $cwd =~ /cwd\s+->\s+(\S+)/ ) {
        $dir = $1;
    }

    my $bin_dir = dirname($dir);
    eval { chdir($bin_dir) };
    if ($@) { print "chdir failed :$@\n" }

    my $ver;
    if ( -e 'activemq' ) {
        my $ver_output = `./activemq --version 2>/dev/null`;
        if ( $ver_output =~ /ActiveMQ\s+(\d+\.\d+\.\d+)/ ) {
            $ver = $1;
            $data{'版本'} = $ver;
        }
    }

    my $install_dir = dirname($bin_dir);
    $data{'安装路径'} = $install_dir;

    my $port;
    if ( -e "$install_dir/conf/activemq.xml" ) {
        my $xml   = `cat $install_dir/conf/activemq.xml`;
        my @ports = $xml =~ /static:\(nio:\/\/\d+\.\d+\.\d+\.\d+:(\d{4,5})/g;

        if ( @ports == 0 ) {
            $port = '';
        }
        else {
            $port = join( ',', @ports );
            $data{'端口'} = $port;
        }
    }

    push( @collect_data, \%data );
    return @collect_data;
}

1;
