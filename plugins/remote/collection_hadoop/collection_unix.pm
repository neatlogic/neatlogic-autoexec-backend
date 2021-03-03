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

    my $pro_hdp = `ps -ef | grep Dhadoop.home.dir|grep -v grep`;
    if ( !$pro_hdp ) {
        print "not hdp\n";
        exit(0);
    }
    my @arr_inst_path = $pro_hdp =~ /(?<=-Dhadoop\.home\.dir=)(\S+)(?=\s)/g;
    @arr_inst_path = do {
        my %seen;
        grep { !$seen{$_}++ } @arr_inst_path;
    };
    if ( @arr_inst_path != 0 ) {
        foreach my $inst_path (@arr_inst_path) {
            my %data = ();
            $data{'安装路径'} = $inst_path;
            my $bin_path = $inst_path . '/bin';
            chdir($bin_path);
            if ( -e "hadoop" ) {
                my $ver = `./hadoop version|head -n1`;
                chomp($ver);
                $data{'版本'} = $ver;
            }
            else {
                my $ver = `hadoop version|head -n1`;
                chomp($ver);
                $data{'版本'} = $ver;
            }

            my $name = `hostname`;
            chomp($name);

            $data{'名称'}      = $name;
            $data{'中间件类型'}   = 'hadoop';
            $data{'IP'}      = $nodeIp;
            $data{'agentIP'} = $nodeIp;
            $data{'部署于'}     = $nodeIp;

            my $port;
            $data{'端口'} = $port;
            push(@collect_data , \%data);
        }
    }
    return @collect_data;
}

1;
