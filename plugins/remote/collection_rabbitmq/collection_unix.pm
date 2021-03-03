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

    my $pro = `ps -ef | grep rabbitmq|grep -v grep`;
    if ( !$pro ) {
        print "not find rabbitmq .\n";
        exit(0);
    }

    $data{'IP'}      = $nodeIp;
    $data{'agentIP'} = $nodeIp;
    $data{'部署于'}     = $nodeIp;
    my $host = `hostname`;
    chomp($host);
    $data{'名称'} = $host;

    my $type = 'rabbitmq';
    $data{'中间件类型'} = $type;

    if ( $pro =~ /(?<=-pa\s)(\S+)/ ) {
        my $path = dirname($1);
        $data{'安装路径'} = $path;
    }
    my $sbin_dir = $data{'安装路径'} . '/sbin';
    chdir($sbin_dir);
    print $sbin_dir;

    if ( -e 'rabbitmqctl' ) {
        my $ver_info = `sudo -u rabbitmq ./rabbitmqctl status|grep {rabbit,`;
        if ( $ver_info =~ /\d+\.\d+\.\d+/ ) {
            $data{'版本'} = $&;
        }
        my $port_info = `sudo -u rabbitmq ./rabbitmqctl status|grep listeners`;
        my @ports     = $port_info =~ /\d+/g;
        if ( @ports != 0 ) {
            my $str_port = join( ',', @ports );
            $data{'端口'} = $str_port;
        }
    }
    push(@collect_data , \%data);
    return @collect_data;
}

1;
