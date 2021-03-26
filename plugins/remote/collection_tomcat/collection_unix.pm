package collection_unix;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;
use File::Basename;

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();
    my @collect_data =();
    my %data = ();

    my $tomcat_info = `ps -ef|grep org.apache.catalina.startup.Bootstrap |grep -v grep|head -n1`;
    my @info_splits = split /\s+/, $tomcat_info;
    my $process_id  = $info_splits[1];

    if ( !$tomcat_info or $tomcat_info =~ /tomcat-\d+\.\d+/ ) {
        print "can't find tomcat process .\n";
        return @collect_data;
        exit 0;
    }

    my $os_name = `hostname`;
    chomp($os_name);
    $data{'名称'} = $os_name;

    my $ip = $nodeIp;
    $data{'IP'} = $ip;
    $data{'agentIP'} = $ip;
    my $install_path;
    if ( $tomcat_info =~ /-Dcatalina.home=(\S+)\s+/ ) {
        $install_path = $1;
        $data{'安装路径'} = $install_path;
    }

    my $version_path = $install_path . '/bin';
    chdir($version_path);

    #目录授权
    my $testVer = `./version.sh`;
    if ( not defined($testVer) or $testVer eq '' ) {
        system(`chmod 777 $version_path/*.sh`);
    }
    
    my @ver_out = `./version.sh`;
    foreach my $line (@ver_out){
        if($line =~ /Server number/ ){
            my @values = split /:/, $line;
            my $ver = @values[1];
            $ver =~ s/^\s+|\s+$//g;
            $data{'版本'} = $ver;
        }
        if($line =~ /CATALINA_HOME/ ){
            my @values = split /:/, $line;
            my $catalina_home = @values[1];
            $catalina_home =~ s/^\s+|\s+$//g;
            $data{'CATALINA_HOME'} = $catalina_home;
        }
        if($line =~ /JVM Vendor/ ){
            my @values = split /:/, $line;
            my $jvm_vendor = @values[1];
            $jvm_vendor =~ s/^\s+|\s+$//g;
            $data{'JDK厂商'} = $jvm_vendor;
        }
    }

    my $java_home = `xargs --null --max-args=1 < /proc/$process_id/environ|grep -E ^JAVA_HOME|cut -d = -f 2`;
    if ( defined $java_home and $java_home ne '' ) {
        chomp($java_home);
        my $java_path = $java_home . '/bin';
        chdir($java_path);

        my $java_ver_output = `./java -version 2>&1`;
        my $java_ver;
        if ( $java_ver_output =~ /(?<=version\s")(\S+)(?=")/ ) {
            $java_ver = $1;
        }
        $data{'JDK版本'} = $java_ver;

    }
    $data{'部署于'} = $ip;

    my @process = `ps -ef|grep org.apache.catalina.startup.Bootstrap|grep -v grep`;
    my @arr_instance;
    foreach my $pro (@process) {
        my %tomcat = ();
        my $catalina_base;
        if ( $pro =~ /Dcatalina.base=(\S+)\s+/ ) {
            $catalina_base = $1;
        }
        my $instance_port;
        if ( $pro =~ /Dhttp.port=(\S+)\s+/ ) {
            $instance_port = $1;
            $tomcat{'端口'} = $instance_port;
        }
        else {
            my $ser_xml = `cat $catalina_base/conf/server.xml`;
            my $port;
            if ($ser_xml =~ /\bConnector\b.*\bHTTP\b/){
            	my $a = $&;
            	if ($a =~ /port="(\d+)"/){
            		$port = $1;
            	}
            }
            $tomcat{'端口'} = $port;
        }
        $tomcat{'服务名'} = basename($catalina_base);
        $tomcat{'应用IP'}       = $ip;

        my @jmx_params = ();
        my @lines = split /\s+/, $pro;
        foreach my $line (@lines){
            chomp($line);
            if($line =~ /^-X/ ){
                push(@jmx_params , $line);
            }
        }
        $tomcat{'JMX参数'}= \@jmx_params;
        push @arr_instance, \%tomcat;
        
    }
    $data{'包含实例'} = \@arr_instance;
    push(@collect_data , \%data);
    
    return @collect_data;
}

1;
