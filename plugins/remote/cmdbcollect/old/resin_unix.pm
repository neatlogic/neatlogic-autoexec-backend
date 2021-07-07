#!/usr/bin/perl

package resin_unix;

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
    my @collect_data = ();

    my $pro_resin = `ps -ef | grep Dresin.home |grep -v grep`;
    if ( !$pro_resin ) {
        print "not find resin process.\n";
        return @collect_data;
        exit(0);
    }
    my @arr_inst_path = $pro_resin =~ /(?<=-Dresin\.home=)(\S+)(?=\s)/g;
    @arr_inst_path = do {
        my %seen;
        grep { !$seen{$_}++ } @arr_inst_path;
    };
    if ( @arr_inst_path != 0 ) {
        foreach my $inst_path (@arr_inst_path) {
            my %data = ();
            $data{'安装路径'} = $inst_path;
            my $lib_path = $inst_path . '/lib';
            chdir($lib_path);
            my $ver = `java -classpath ./resin.jar com.caucho.Version|head -n1|awk '{print \$1'}`;
            chomp($ver);
            $data{'版本'} = $ver;
            my $name = `hostname`;
            chomp($name);

            $data{'名称'}          = $name;
            $data{'中间件类型'} = 'resin';
            $data{'IP'}              = $nodeIp;
            $data{'部署于'}       = $nodeIp;
            $data{'agentIP'}         = $nodeIp;

            my $port;
            my $config_path = $inst_path . '/conf/resin.conf';
            my $line        = `cat $config_path`;
            my @ports       = $line =~ /\n\s+<http\s+address="\*"\s+port="(\d+)"/g;
            $port = join( ',', @ports );

            $data{'端口'} = $port;
            push( @collect_data, \%data );
        }
    }

    return @collect_data;
}

1;
