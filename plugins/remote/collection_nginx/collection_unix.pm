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

    my $nginx_pro = `ps -ef|grep nginx|grep master|grep -v grep`;

    if ( !defined $nginx_pro or $nginx_pro eq '' ) {
        print "not find nginx process .\n";
        return @collect_data;
        exit 0;
    }
    else {
        my $has_c_opt = 0;
        my $c_conf_path;
        my $c_base_dir;
        if ( $nginx_pro =~ /(?<=-c\s)(\S+)(?=\s)/ ) {
            $has_c_opt = 1;
            my $tmp = $1;
            $c_conf_path = dirname($tmp);
            $c_base_dir = dirname($c_conf_path);
        }

        my @arr       = split /\s+/, $nginx_pro;
        my $pid    = $arr[1];
        my $host_name = `hostname`;
        chomp($host_name);
        $data{'名称'} = $host_name;

        my $ip = $nodeIp;
        $data{'IP'}    = $ip;
        $data{'agentIP'}= $ip;
        $data{'部署于'}    = $ip;
        $data{'中间件类型'} = 'nginx';

        my $abs_ng_path = `ls -al /proc/$pid/exe|awk '{print \$NF}'`;
        my $bin_dir  = dirname($abs_ng_path);
        chdir($bin_dir);

        my $ver;
        my $base_dir;
        my @nginx_info = `./nginx -V |& awk '{print \$0}'`;
        foreach my $line ( @nginx_info ){
            if($line =~ /nginx version:/){
                my @values = Utils::str_split($line, ':');
                $ver = @values[1] || '';
                $ver = Utils::str_trim($ver); 
            }
            if($line =~ /configure arguments:/){
                my @values = Utils::str_split($line, ':');
                my $cfg = @values[1];
                $cfg = Utils::str_trim($cfg); 
                if($cfg =~ /--prefix=/){
                    my @values = Utils::str_split($cfg, '=');
                    $base_dir = @values[1] || '';
                    $base_dir = Utils::str_trim($base_dir); 
                }
            }
        }
        $data{'版本'} = $ver;

        if(not defined($base_dir) or $base_dir eq '' ){
            $base_dir = dirname(dirname($abs_ng_path));
            if ($has_c_opt == 1 ){
                $base_dir = $c_base_dir;
            }
        }
        $data{'安装路径'} = $base_dir;
        my $conf_dir = $base_dir."/conf";
        if ($has_c_opt == 1){
            $conf_dir = $c_conf_path;
        }

        my $nginx_conf_file = $conf_dir . "/" . "nginx.conf";
        $data{'服务配置'} = get_server_config($nginx_conf_file);
        push(@collect_data , \%data);
    }
    return @collect_data;
}

sub get_conf_server {
    my($conf_path ) = @_ ;
    my @server_cfg = ();
    open( FILE, "< $conf_path " ) or die "can not open file: $!";
    my $server = '';
    my $startCount = 0 ;
    my $endCount = 0 ;
    while ( my $read_line = <FILE> ) {
        chomp($read_line);
        
        if ( ($read_line =~ /server/ and $read_line =~ /\{/) or ($startCount > 0 and $read_line =~ /\{/ ) ){ 
            $startCount = $startCount + 1;
        }
        if( $startCount > 0 and $read_line =~ /\}/ ){
            $endCount = $endCount + 1;
        }
    
        if($startCount > 0 and $startCount >= $endCount){
            $server = $server."\n".$read_line;
        }

        if($startCount == $endCount and $server ne '' ){
            push @server_cfg, $server;
            $server = '';
            $startCount = 0 ; 
            $endCount = 0 ;
        }
    }
    close(FILE);
    return @server_cfg;
} 

sub get_conf_include {
    my($conf_path) = @_ ;
    my @includes = ();
    push @includes , $conf_path ;
    open( FILE, "< $conf_path " ) or die "can not open file: $!";
    while ( my $read_line = <FILE> ) {
        chomp($read_line);
        if( $read_line =~ /include/  and  $read_line !~ /mime.types/){
            my $path = $read_line;
            $path =~ s/include//;
            $path =~ s/;//;
            $path = Utils::str_trim($path);
            my $e = rindex($path , '/');
            my $dir = substr( $path, 0, $e );
            my $file = substr( $path, $e + 1 , length($path));
            if (-d $dir ) {
                $dir = $dir ;
            }else{
                my $root = dirname($conf_path);
                $dir = $root . "/" . $dir ; 
            }
            if( $file =~ /\*/ ){
                $dir =  $dir . "/" . $file ;
                my @files = glob( $dir );
                foreach my $file (@files ){
                    push @includes , $file ;
                }
            }else{
                my $tmp = $dir . "/" . $file;
                if(-e $tmp ){
                    push @includes , $tmp ;
                }
            }
        }
    }
    close(FILE);
    return @includes;
}

sub get_config_param {
    my( $data , $cfg ) = @_ ;
    my @lines = split( /[\r\n]+/, $data );
    my %nginx = ();
    $nginx{'conf路径'} = $cfg;
    
    my $port = '';
    my $server_name = '';
    my $type = 'http';
    my $status  = '未配置';
    foreach my $line (@lines) {
        chomp($line);
        if($line =~ /listen/){
            $port = $line;
            $port  =~ /(\d+)/;
            $port = Utils::str_trim($1);
        }
        
        if($line =~ /server_name/){
            $server_name = $line;
            $server_name =~ s/;//;
            $server_name = Utils::str_trim($server_name);
        }

        if($line =~ /ssl/){
            $type  = 'https';
        }

        if($line =~ /\/status/){
            $status  = '开启';
        }
    }
    $nginx{'代理端口'}  = $port;
    $nginx{'代理名称'}  = $server_name;
    $nginx{'类型'}  = $type;
    $nginx{'status监控'}  = $status;
    return \%nginx;
}

sub get_server_config{
    my( $conf_path) = @_ ;
    my @includes = get_conf_include($conf_path);
    my @nginx_servers = ();
    foreach my $cfg (@includes){
        my @server_cfg = get_conf_server($cfg);
        foreach my $server (@server_cfg){
            chomp($server);
            my $param = get_config_param($server ,$cfg );
            push(@nginx_servers , $param); 
        }
    }
    return \@nginx_servers;
}

1;
