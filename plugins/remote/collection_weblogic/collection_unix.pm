package collection_unix;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;
use File::Basename;
use XML::Simple;

sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

sub get_cfgxml {
    my @arr_domain;
    my @arr_process;
    my @arr_config_xml;

    @arr_process = `ps -ef|grep weblogic.Name|grep -v grep|awk '{print \$2}'`;
    chomp(@arr_process);
    foreach my $pid (@arr_process) {
        my $dir    = "/proc/$pid/environ";
        my $d_home = `xargs --null --max-args=1 < $dir |grep -E ^DOMAIN_HOME|cut -d = -f 2`;
        if ( defined $d_home && $d_home ne '' ) {
            push @arr_domain, $d_home;
        }
    }
    my @domains = uniq(@arr_domain);
    chomp(@domains);

    foreach (@domains) {
        my $ab_path = $_ . "/config/config.xml";
        if ( -f $ab_path ) {
            push @arr_config_xml, $ab_path;
        }
    }
    return @arr_config_xml;
}

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();

    my $path_info = `ps -ef|grep weblogic.Name|grep -v grep|head -n1`;
    if ( !$path_info ) {
        print "can't find weblogic.Name process";
        exit 0;
    }

    $path_info =~ /-Djava\.security\.policy=(.*)(wlserver.*)\/server\/lib\/weblogic.policy/;
    my $install_path = $1;
    my $prd_path     = $1 . $2;

    my @arr_config_xml = get_cfgxml();

    foreach my $config_path (@arr_config_xml) {
        my %data = ();
        $data{'安装路径'} = $install_path;

        my $domain_home = dirname( dirname($config_path) );
        my @arr_mid_ware;
        my $ip = $nodeIp;

        $data{'IP'}  = $nodeIp;
	    $data{'agentIP'} = $nodeIp;
        $data{'部署于'} = $ip;
        my $osname = `hostname`;
        chomp($osname);
        $data{'名称'}    = $osname;
        $data{'中间件类型'} = 'weblogic';

        my $weblogic_pid = `ps -ef|grep weblogic.Name |grep -v grep|awk '{print \$2}'|head -n 1`;
        chomp($weblogic_pid);
        my $java_home = `xargs --null --max-args=1 < "/proc/$weblogic_pid/environ" |grep -E ^JAVA_HOME|cut -d = -f 2`;
        chomp($java_home);
        if ( $java_home =~ /\/(jdk.*)/ ) {
            $data{'JDK版本'} = $1;
        }

        $data{'安装路径'} = $install_path;

        my $xml     = XMLin($config_path);
        my $version = $xml->{'domain-version'};
        $data{'版本'} = $version;
        my $domain_name = $xml->{'name'};
        $data{'weblogic域名'}  = $domain_name;
        $data{'domain_home'} = $domain_home;

        my $patch_info;
        if ( $version =~ /^10\./ ) {
            my $bsu_home = $install_path . 'utils/bsu';
            if ( -d $bsu_home ) {
                chdir($bsu_home);
                if ( -f 'bsu.sh' ) {
                    my $user = getpwuid( ( stat('bsu.sh') )[4] );

                    my $patch_output = `sudo -u $user sh bsu.sh -prod_dir=$prd_path -status=applied -verbose -view`;
                    my @arr_patch    = $patch_output =~ /Patch\s+ID:\s+(\w+)\s+/g;

                    if ( @arr_patch != 0 ) {
                        $patch_info = join( ',', @arr_patch );
                        $data{'补丁情况'} = $patch_info;
                    }
                }
            }
        }
        elsif ( $version =~ /^12\./ ) {

            my $opatch_home = $install_path . 'OPatch';
            if ( -d $opatch_home ) {
                chdir($opatch_home);
                if ( -f 'opatch' ) {
                    my $user         = my $user = getpwuid( ( stat('opatch') )[4] );
                    my $patch_output = `sudo -u $user ./opatch lsinventory`;

                    my @arr_patch = $patch_output =~ /Patch\s+(\d+)\s+:/g;

                    if ( @arr_patch != 0 ) {
                        $patch_info = join( ',', @arr_patch );
                        $data{'补丁情况'} = $patch_info;
                    }
                }
            }
        }

        my $server = $xml->{'server'};
        my @arr_instances;
        if ( defined $server ) {
            foreach my $server_name ( keys %$server ) {
                my $server_ins = $server->{$server_name};
                my %intance    = ();
                $intance{'服务名'} = $server_name;

                if ( ref( $server_ins->{'listen-address'} ) ne 'HASH' && defined $server_ins->{'listen-address'} ) {
                    $intance{'应用IP'} = $server_ins->{'listen-address'};
                }
                else {
                    $intance{'应用IP'} = $ip;
                }

                my $process = `ps -ef |grep Dweblogic.Name=$server_name |grep -v grep`;
                my @lines   = split /\s+/, $process;
                my $user    = @lines[0] || "";
                chomp($user);
                $intance{'启动用户'} = $user;

                if ( $server_name eq 'AdminServer' ) {
                    my $pid = @lines[1];
                    chomp($pid);
                    my $process_port  = `netstat -tlpn 2>/dev/null | grep $pid | awk '{ print \$4 }' | tr '\n' ',' | tr ' ' ',' | grep -o ":....," | sort -u | tr -d '\n' | tr -d ':' | sed 's/,\$//'`;
                    my @process_ports = split( /,/, $process_port );
                    if ( scalar(@process_ports) == 1 ) {
                        $intance{'端口'} = @process_ports[0];
                    }
                    else {
                        $intance{'端口'} = \@process_ports;
                    }
                    $data{'端口'} = @process_ports[0];
                }
                else {
                    next if ( !defined $server_ins->{'listen-port'} or $server_ins->{'listen-port'} eq '' );
                    $intance{'端口'} = $server_ins->{'listen-port'};
                }

                my @jmx_params = ();
                foreach my $line (@lines) {
                    chomp($line);
                    if ( $line =~ /^-X/ ) {
                        push( @jmx_params, $line );
                    }
                }
                $intance{'JMX参数'} = \@jmx_params;

                if ( exists( $server_ins->{'cluster'} ) ) {
                    $intance{'是否集群'} = '是';
                }
                else {
                    $intance{'是否集群'} = '否';
                }
                push @arr_instances, \%intance;
            }
        }
        $data{'包含实例'} = \@arr_instances;
        push(@collect_data , \%data);
    }
    return @collect_data;
}

1;
