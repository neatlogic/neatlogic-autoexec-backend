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

sub sqlplusRun {
    my ( $oracle_home, $sid, $cmd, $user ) = @_;
    my $ORACLE_HOME = $oracle_home;
    my $PATH        = $ENV{'PATH'};
    if ( not defined($user) or $user eq '' ) {
        $user = 'oracle';
    }
    my $runPath = qq(export ORACLE_HOME=$ORACLE_HOME;export ORACLE_SID=$sid;export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH);
    my $execute = "su - $user -c '$runPath;sqlplus -s / as sysdba' << EOF
$cmd
exit; 
EOF";
    my $result = `$execute`;
    return $result;
}

sub localRun {
    my ( $oracle_home, $sid, $cmd, $user ) = @_;
    if ( not defined($user) or $user eq '' ) {
        $user = 'oracle';
    }
    my $ORACLE_HOME = $oracle_home;
    my $PATH        = $ENV{'PATH'};
    my $runPath     = qq(export ORACLE_HOME=$ORACLE_HOME;export ORACLE_SID=$sid;export PATH=$ORACLE_HOME/bin:$ORACLE_HOME/OPatch:$PATH);
    my $result      = `su - $user -c '$runPath;$cmd'`;
    return $result;
}

sub get_pubip {
    my ($nodeIp) = @_;
    my $pubip;
    my $hostname = `hostname`;
    chomp($hostname);
    my @hosts_file = `cat /etc/hosts|grep "^[^#]"`;
    foreach (@hosts_file) {
        if (/^(\d+\.\d+\.\d+\.\d+)\s+\Q$hostname\E$/) {
            $pubip = $1;
            last;
        }

    }
    if ( !defined $pubip or $pubip eq '' ) {
        $pubip = $nodeIp;
    }
    return $pubip;
}

sub get_dbid {
    my ( $oracle_home, $sid ) = @_;
    my $query  = q(select dbid from v\$database;);
    my $result = sqlplusRun( $oracle_home, $sid, $query );
    $result =~ s/^\s+|\s+$//g;
    my @arr0 = split /\n/, $result;
    my $dbid = @arr0[-1];
    $dbid =~ s/^\s+|\s+$//g;
    return $dbid;
}

sub get_grid_version {
    my ( $oracle_home, $sid ) = @_;
    my $query  = q(select substr(banner,instr(banner,'Release')+7,11) from v\$version where rownum <=1;);
    my $result = sqlplusRun( $oracle_home, $sid, $query );
    $result =~ s/^\s+|\s+$//g;
    my @result_arr = split /\n/, $result;
    my $grid_ver   = $result_arr[-1];
    $grid_ver =~ s/^\s+|\s+$//g;
    return $grid_ver;
}

sub getpdb_servername {
    my ( $oracle_home, $sid, $pdb ) = @_;
    my @servername_arr;
    my $pdbname     = $pdb->{'PDB名称'};
    my %server_name = ();
    my $query       = qq(
        alter session set container=$pdbname;
        set linesize 300 pagesize 999;
        select name from dba_services where name not like 'SYS%';
    );
    my $result = sqlplusRun( $oracle_home, $sid, $query );
    $result =~ s/^\s+|\s+$//g;
    @servername_arr = split /\n/, $result;
    @servername_arr = grep { $_ !~ /^\s*$|selected|Session/ } @servername_arr;

    if ( $servername_arr[0] =~ /mail/i ) {
        @servername_arr = @servername_arr[ 2 .. $#servername_arr ];
    }
    @servername_arr = @servername_arr[ 2 .. $#servername_arr ];
    $pdb->{'包含服务名'} = \@servername_arr;

    #return @servername_arr;
}

sub get_pdb_name {
    my ( $oracle_home, $sid ) = @_;
    my $pdbname_query  = q(select name,con_id from v\$pdbs where name<>'PDB\$SEED';);
    my $pdbname_result = sqlplusRun( $oracle_home, $sid, $pdbname_query );
    $pdbname_result =~ s/^\s+|\s+$//g;
    my @pdbname_arr = split /\n/, $pdbname_result;
    @pdbname_arr = grep { $_ !~ /^\s*$|selected|Session/ } @pdbname_arr;
    if ( $pdbname_arr[0] =~ /mail/i ) {
        @pdbname_arr = @pdbname_arr[ 2 .. $#pdbname_arr ];
    }
    @pdbname_arr = @pdbname_arr[ 2 .. $#pdbname_arr ];
    my @pdb_names;
    foreach (@pdbname_arr) {
        my @tmp = split /\s+/, $_;
        push @pdb_names, $tmp[0];
    }
    return @pdb_names;
}

sub get_pdb {
    my ( $oracle_home, $sid ) = @_;
    my $pdbsQuery = q(
        set linesize 200;     
        set pagesize 1000;
        col NAME format a12; 
        select name,dbid,con_id from v\$pdbs where name<>'PDB\$SEED';
    );
    my $pdbsResult = sqlplusRun( $oracle_home, $sid, $pdbsQuery );
    $pdbsResult =~ s/^\s+|\s+$//g;
    my @pdbs_arr = split /\n/, $pdbsResult;
    @pdbs_arr = grep { $_ !~ /^\s*$|selected|Session/ } @pdbs_arr;
    if ( $pdbs_arr[0] =~ /mail/i ) {
        @pdbs_arr = @pdbs_arr[ 2 .. $#pdbs_arr ];
    }
    @pdbs_arr = @pdbs_arr[ 2 .. $#pdbs_arr ];
    my @pdbs;
    foreach (@pdbs_arr) {
        my %pdb = ();
        my @tmp = split /\s+/, $_;
        $pdb{'PDB名称'} = $tmp[0];
        $tmp[1] =~ s/^\s+|\s+$//g;
        $pdb{'DBID'}   = $tmp[1];
        $pdb{'con_id'} = $tmp[2];
        push @pdbs, \%pdb;
    }
    return @pdbs;
}

sub get_isRAC {
    my ( $oracle_home, $sid ) = @_;
    my $clusterDatabaseQuery = q(
        set linesize 300 pagesize 999 echo off feedback off heading off underline off;
        select name,value from v\$parameter where name='cluster_database';
    );
    my $clusterDatabaseResult = sqlplusRun( $oracle_home, $sid, $clusterDatabaseQuery );
    my $res;
    if ( $clusterDatabaseResult =~ /TRUE/ ) {
        $res = '是';
    }
    else {
        $res = '否';
    }
    return $res;
}

sub get_user_info {
    my ( $oracle_home, $sid, $pdb ) = @_;
    my @arr_user_info;
    my $pdbname = $pdb->{'PDB名称'};
    my $query   = qq(
        alter session set container=$pdbname;
        set linesize 300 pagesize 1000   
        col username for a25                               
        col default_tablespace for a50;  
        select  du.username, du.default_tablespace from dba_users du where du.account_status='OPEN' and du.default_tablespace not in('SYSTEM','SYSAUX') order by 1,2;
    );
    my $result = sqlplusRun( $oracle_home, $sid, $query );
    $result =~ s/^\s+|\s+$//g;
    my @user_arr = split /\n/, $result;
    @user_arr = grep { $_ !~ /^\s*$|selected|Session/ } @user_arr;

    if ( $user_arr[0] =~ /mail/i ) {
        @user_arr = @user_arr[ 2 .. $#user_arr ];
    }
    @user_arr = @user_arr[ 2 .. $#user_arr ];

    foreach (@user_arr) {
        my @tmp       = split /\s+/, $_;
        my %user_info = ();
        $user_info{'用户'}      = $tmp[0];
        $user_info{'缺省数据表空间'} = $tmp[1];
        push @arr_user_info, \%user_info;
    }
    $pdb->{'包含用户'} = \@arr_user_info;
}

sub get_data_tablespace {
    my ( $oracle_home, $sid, $pdb ) = @_;
    my @arr_data_tablespace;
    my $pdbname = $pdb->{'PDB名称'};

    my %data_tablespace = ();
    my $tablespaceQuery = qq(
        alter session set container=$pdbname;
        set linesize 300 pagesize 1000;
        select distinct tablespace_name from dba_data_files;
    );
    my $tablespaceResult = sqlplusRun( $oracle_home, $sid, $tablespaceQuery );
    $tablespaceResult =~ s/^\s+|\s+$//g;
    my @tablespace_arr = split /\n/, $tablespaceResult;
    @tablespace_arr = grep { $_ !~ /^\s*$|selected|Session/ } @tablespace_arr;

    if ( $tablespace_arr[0] =~ /mail/i ) {
        @tablespace_arr = @tablespace_arr[ 2 .. $#tablespace_arr ];
    }
    @tablespace_arr = @tablespace_arr[ 2 .. $#tablespace_arr ];
    $pdb->{'包含表空间'} = \@tablespace_arr;

    my @arr_data_file;
    my $datafileQuery = qq(
        alter session set container=$pdbname;
        set linesize 250                                               
        set pagesize 1000                                              
        break on tablespace_name                                       
        column tablespace_name format a25                              
        column file_name format a100                                                                          
        column autoextensible format a10                           
        select tablespace_name tbsname,file_name,round(bytes/1024/1024/1024, 2), autoextensible from dba_data_files order by 1,3 asc;
    );
    my $datafileResult = sqlplusRun( $oracle_home, $sid, $datafileQuery );
    $datafileResult =~ s/^\s+|\s+$//g;
    my @datafile_arr = split /\n/, $datafileResult;
    @datafile_arr = grep { $_ !~ /^\s*$|selected|Session/ } @datafile_arr;

    if ( $datafile_arr[0] =~ /mail/i ) {
        @datafile_arr = @datafile_arr[ 2 .. $#datafile_arr ];
    }
    @datafile_arr = @datafile_arr[ 2 .. $#datafile_arr ];

    foreach (@datafile_arr) {
        my %data_file = ();
        my @tmp       = split /\s+/, $_;
        $data_file{'tablespace_name'} = $tmp[0];
        $data_file{'File_Name'}       = $tmp[1];
        $data_file{'大小'}              = $tmp[2];
        $data_file{'Auto_EXT'}        = $tmp[3];
        push @arr_data_file, \%data_file;
    }
    $pdb->{'包含表文件'} = \@arr_data_file;
}

sub collect {
    my ($nodeIp) = @_;
    my @collect_data =();    

    my $is_oracle = `ps -ef|grep oracle|grep -v grep`;
    if ( !$is_oracle ) {
        print "not find oracle process .\n";
        return @collect_data;
        exit 0;
    }

    my $os_type = `uname`;
    chomp($os_type);
    my @arr_ins;
    my @or_home;
    if ( $os_type eq 'Linux' ) {
        my @arr_ins_tmp = `ps -ef|grep pmon|grep ora_|awk '{print \$8}'|grep -v sh`;
        chomp(@arr_ins_tmp);
        my @arr_proc = `ps -ef|grep pmon|grep ora_|grep -v sh|awk '{print \$2}'`;
        chomp(@arr_proc);

        foreach (@arr_ins_tmp) {
            if (/_(\w+)_(\w+)$/) {
                push @arr_ins, $2;
            }
        }
        foreach my $i (@arr_proc) {
            my $dir = "/proc/$i/environ";
            my $a   = `cat $dir |tr '\\0' '\\n'|grep ORACLE_HOME|cut -d = -f 2`;
            push @or_home, $a;
        }
    }
    else {
        my @arr_ins_tmp = `ps -ef|grep pmon|grep ora_|awk '{print \$9}'`;
        chomp(@arr_ins_tmp);
        my @arr_proc = `ps -ef|grep pmon|grep ora_|awk '{print \$2}'`;
        chomp(@arr_proc);

        foreach (@arr_ins_tmp) {
            if (/_(\w+)_(\w+)$/) {
                push @arr_ins, $2;
            }
        }
        foreach my $proc (@arr_proc) {
            my $a = `ps ewww $proc|grep ORACLE_HOME`;
            if ( $a =~ /ORACLE_HOME=(\S+)\s+/ ) {
                push @or_home, $1;
            }
        }
    }
    chomp(@arr_ins);
    chomp(@or_home);

    my $isCDB;
    my $oracle_home;
    my $sid;
    for ( my $i = 0 ; $i < scalar @arr_ins ; $i++ ) {
        $oracle_home = $or_home[$i];
        $sid         = $arr_ins[$i];

        my $isddbQuery  = 'show parameter enable_pluggable_database;';
        my $isddbResult = sqlplusRun( $oracle_home, $sid, $isddbQuery );
        if ( $isddbResult =~ /TRUE/ ) {
            $isCDB = 1;
            last;
        }
        else {
            $isCDB = 0;
            last;
        }
    }

    if ($isCDB) {
        my %data = ();
        my $dbid = get_dbid( $oracle_home, $sid );
        $data{'DBID'}    = $dbid;
        $data{'agentIP'} = $nodeIp;
        $data{'DB类型'}    = 'Oracle';
        my $port_info = localRun( $oracle_home, $sid, "lsnrctl status |grep PORT|head -n1" );
        my $db_port;
        if ( $port_info =~ /PORT=(\d+)/ ) {
            $db_port = $1;
        }
        $data{'服务端口'}  = $db_port;
        $data{'CDB类型'} = 'CDB';
        $data{'GI版本号'} = get_grid_version( $oracle_home, $sid );

        my $is_rac = get_isRAC( $oracle_home, $sid );
        my $scan_ip;
        if ( $is_rac eq '否' ) {
            $scan_ip = $nodeIp;
        }
        else {
            $scan_ip = `grep "^[^#]" /etc/hosts|grep -i SCAN |head -n 2|tail -n1|awk '{print \$1}'`;
            $scan_ip =~ s/^\s+|\s+$//g;
            if ( !defined $scan_ip or $scan_ip eq '' ) {
                $scan_ip = get_pubip($nodeIp);
            }
        }
        $data{'服务IP'} = $scan_ip;

        my $grid_home = localRun( $oracle_home, $sid, "env|grep ORACLE_HOME|cut -d = -f 2", 'grid' );
        if ( !defined $grid_home or $grid_home eq '' ) {
            $grid_home = '';
        }
        chomp($grid_home);
        $data{'GRID_HOME'} = $grid_home;

        my @pdbs      = get_pdb( $oracle_home, $sid );
        my @con_names = get_pdb_name( $oracle_home, $sid );

        foreach my $pdb (@pdbs) {
            getpdb_servername( $oracle_home, $sid, $pdb );
            get_user_info( $oracle_home, $sid, $pdb );
            get_data_tablespace( $oracle_home, $sid, $pdb );
        }
        $data{'包含PDB'} = \@pdbs;
        push(@collect_data , \%data);
    }

    return @collect_data;
}

1;
