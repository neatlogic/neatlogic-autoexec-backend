package collection_unix;

#!/usr/bin/perl
use FindBin;
use lib "$FindBin::Bin/../lib/perl-lib/lib/perl5";
use lib "$FindBin::Bin/../lib";

use strict;
use utf8;
use File::Basename;
use Encode;

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();
    my %data = ();

    my @pro_was = `ps -ef|grep com.ibm.ws|grep -v grep`;
    if ( @pro_was == 0 ) {
        print 'not find websphere process .\n';
        return @collect_data;
        exit 0;
    }

    my @result;
    @pro_was = grep( !/nodeagent/, @pro_was );

    my $os = `uname`;
    chomp($os);
    my $host_ip= $nodeIp;
    my $name = `hostname`;
    chomp($name);
    $data{'名称'} = $name;
    $data{'IP'} = $host_ip;
    $data{'agentIP'} = $host_ip;
    $data{'部署于'}        = $host_ip;
    $data{'中间件类型'} = 'WebSphere';

    foreach my $pro (@pro_was) {
        my $java_path;
        if ( $pro =~ /(?<=\s)(\S+\/bin)\/java(?=\s)/ ) {
            $java_path = $1;
        }

        chdir($java_path);
        my $java_ver_output = `java -version 2>&1`;
        my $java_ver;
        if ( $java_ver_output =~ /(?<=version\s")(\S+)(?=")/ ) {
            $java_ver = $1;
        }
        $data{'JDK版本'}    = $java_ver;

        my $install_path;
        if ( $pro =~ /(?<=-Dosgi\.install\.area=)(\S+)(?=\s)/ ) {
            $install_path = $1;
        }
        $data{'安装路径'} = $install_path;

        my $ver_path = $install_path . '/bin';
        chdir($ver_path);

        my $was_ver;
        my $wasver_output = `./versionInfo.sh`;
        my $previousLine;
        my @wasver_rsa = split( /\n/, $wasver_output );
        foreach my $line (@wasver_rsa) {
            my $rexstr1 = encode( 'utf-8', '版本目录' );
            my $rexstr2 = encode( 'utf-8', '版本' );
            if ( $line =~ /Version Directory/ or $line =~ /$rexstr1/ ) {
                #continue ;
            }
            elsif ( $line =~ /^$rexstr2/ or $line =~ /^Version/ ) {
                if ( $previousLine =~ /IBM WebSphere Application Server/ ) {
                    my @tmp = split( ' ', $line );
                    $was_ver = $tmp[1];
                    $was_ver =~ s/^\s+|\s+$//g;
                }
            }
            $previousLine = $line;
        }
        $data{'版本'} = $was_ver;
        last ;
    }

    my @was_instances = ();
    foreach my $pro (@pro_was) {
        my %was_instance = ();
        $was_instance{'应用IP'} = $host_ip;
        $pro =~ s/^\s+|\s+$//g;
        my @splits      = split /\s+/, $pro;
        my $server_name = $splits[-1];
        my $node_name   = $splits[-2];
        my $cell_name   = $splits[-3];
        my $config_path = $splits[-4];
        $was_instance{'名称'} = $server_name;

        my $xml_path = $config_path . '/cells/' . $cell_name . '/nodes/' . $node_name . '/serverindex.xml';
        my $manage_info = `cat $xml_path`;
        $manage_info =~ /<serverEntries.*?serverName="$server_name"(.*?)<\/serverEntries>/s;
        $manage_info = $1;
        my $manage_port;
        if ( $manage_info =~ /"WC_adminhost">.*?port="(.*?)".*?<\/specialEndpoints>/s ) {
            $manage_port = $1;
        }
        $was_instance{'管理端口'}     = $manage_port;
        $was_instance{'agent_ip'} = $nodeIp;
        my $app_port = '-';
        if ( $manage_info =~ /"WC_defaulthost">.*?port="(.*?)".*?<\/specialEndpoints>/s ) {
            $app_port = $1;
        }
        $was_instance{'应用端口'} = $app_port;

        my $manage_info = `cat $xml_path`;
        $manage_info =~ /<serverEntries.*?serverName="$server_name"(.*?)<\/serverEntries>/s;
        $manage_info = $1;

        my @arr_app = ();
        my $app_path = $config_path . '/..' . '/temp/' . $node_name . '/' . $server_name . '/*';
        my @apps     = glob($app_path);
        for my $ins (@apps) {
            if ( ( $ins !~ /_extensionregistry/ ) and ( $ins !~ /ibmasyncrsp/ ) and ( $ins !~ /filetransferSecured/ ) ) {
                push @arr_app, basename($ins);
            }
        }
        $was_instance{'应用'} = \@arr_app;

        my $Registry_path = $config_path . '/cells/' . $cell_name . '/fileRegistry.xml';
        my $user_info     = `cat $Registry_path`;
        my @arr_user           = $user_info =~ /<wim:uid>(.*?)<\/wim:uid>/g;
        my @users = ();
        foreach my $user (@arr_user){
            push @users , $user; 
        };
        $was_instance{'包含用户'} = \@users;

        my @jmx_params = ();
        foreach my $line (@splits) {
            chomp($line);
            if ( $line =~ /^-X/ ) {
                push( @jmx_params, $line );
            }
        }
        $was_instance{'JMX参数'} = \@jmx_params;

        push @was_instances, \%was_instance;
    }
    $data{'包含实例'} = \@was_instances;
    push(@collect_data , \%data);
    
    return @collect_data;
}

1;
