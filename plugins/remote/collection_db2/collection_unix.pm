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
    my ( $nodeIp ) = @_;
    my @collect_data =();
    
    my @db2_ins_users = `ps -ef|grep db2sysc|grep -v grep|awk '{print \$1}'`;
    chomp(@db2_ins_users);

    if ( @db2_ins_users == 0 ) {
        print "no find db2sysc process.\n";
        return @collect_data;
        exit 0;
    }
    
    my $host_ip = $nodeIp;
    foreach my $db2_ins_user (@db2_ins_users) {
        my %data = ();
        $data{'agentIP'} = $nodeIp;
        $data{'数据库类型'} = 'db2';
        $data{'服务IP'}  = $host_ip;

        my $dbid;
        my @arr_server_name;
        my @db2_ins = `su - $db2_ins_user -c 'db2ilist'`;
        @db2_ins = grep { $_ !~ /mail/i } @db2_ins;
        if ( @db2_ins == 0 ) {
            print "no find db2sysc process\n";
            exit 0;
        }
        chomp(@db2_ins);

        my $ver;
        foreach my $user (@db2_ins) {
            my $ver_info = `su - $user -c 'db2level'`;
            if ( $ver_info =~ /"DB2\s+(v\S+)"/ ) {
                $ver = $1;
            }
            $data{'数据库版本'} = $ver;
            $dbid          = $ver;
            $data{'DBID'}  = $dbid;
            last;
        }

        my @arr_users;
        my @arr_ins;
        foreach my $user (@db2_ins) {
            my %ins = ();
            $ins{'IP'}      = $host_ip;
            $ins{'实例名'}     = $user;
            $ins{'安装于操作系统'} = $host_ip;

            my $port;
            my @arr_port_info = `su - $user -c 'db2 get dbm cfg|grep SVC|head -n1|cut -d = -f 2'`;
            @arr_port_info = grep { $_ !~ /mail/i } @arr_port_info;
            my $port_info = $arr_port_info[-1];
            $port_info =~ s/^\s+|\s+$//g;
            if ( $port_info =~ /^\d{1,5}$/ ) {
                $port = $&;
            }

            if ( not defined($port) or $port eq '' ) {
                my $ser_port = `cat /etc/services|grep -w $port_info`;
                if ( !defined $ser_port || $ser_port eq '' ) {
                    print "can't find ins_port in /etc/services\n";
                }
                else {
                    if ( $ser_port =~ /(\d+)\/tcp/ ) {
                        $port = $1;
                    }
                }
            }

            #异常
            if ( ( not defined($port_info) or $port_info eq '' ) and ( not defined($port) or $port eq '' ) ) {
                $port = '50000';
            }

            $ins{'端口'}    = $port;
            $data{'服务端口'} = $port;

            my $db_info = `su - $user -c "db2 list db directory|egrep -i 'Database name|Directory entry type'"`;

            my @db_name_array = $db_info =~ /name\s*=\s*(\S+)/g;
            my @db_type_array = $db_info =~ /type\s*=\s*(\S+)/g;
            my @db_names;
            my $i_count = 0;
            foreach (@db_type_array) {
                if ( $_ =~ /remote/i ) { $i_count++; next; }
                my $tmpname = $db_name_array[$i_count];
                push @db_names, $tmpname;
                $i_count++;
                push @arr_server_name, $tmpname;
            }
            my $db_name = join( ',', @db_names );
            $ins{'库名'} = $db_name;

            push @arr_ins, \%ins;

            foreach (@db_names) {
                my $os_type = `uname`;
                chomp($os_type);
                if ( $os_type eq 'AIX' ) {
                    system("su - $user -c \"db2 connect to $_ \"");
                    my @user_info = `su - $user -c "db2 'select distinct cast((grantee) as char(20)) as "aaa" from syscat.tabauth'"`;
                    if ( $user_info[-1] =~ /not\s+exist/ ) {
                        next;
                    }
                    my @users = grep { $_ !~ /aaa|grantee|--|selected|^\s*$|mail/i } @user_info;
                    s/^\s+|\s+$//g foreach (@users);
                    foreach my $u (@users) {
                        push @arr_users, $u;
                    }
                }
                elsif ( $os_type eq 'Linux' ) {
                    my $b         = "db2 connect to $_";
                    my $a         = "db2 'select distinct cast((grantee) as char(20)) as \"aaa\" from syscat.tabauth'";
                    my @user_info = `su - $user -c "$b && $a"`;
                    if ( $user_info[-1] =~ /not\s+exist/ ) {
                        print "none";
                    }
                    my @users = grep { $_ !~ /aaa|sql|local|database|grantee|--|selected|^\s*$|mail/i } @user_info;
                    s/^\s+|\s+$//g foreach (@users);
                    foreach my $u (@users) {
                        push @arr_users, $u;
                    }
                }
            }
        }

        $data{'数据库实例'} = \@arr_ins;
        $data{'包含用户'}  = \@arr_users;
        $data{'包含服务名'} = \@arr_server_name;
        push(@collect_data , \%data);
    }
    return @collect_data;
}

1;
