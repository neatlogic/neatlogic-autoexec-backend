#!/usr/bin/perl
#采集器模板，复制然后修改类名和填入collect方法的内容
use FindBin;
use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";

use strict;

package GbaseCollector;

use BaseCollector;
our @ISA = qw(BaseCollector);

use Socket;
use File::Spec;
use File::Basename;
use IO::File;
use CollectObjCat;
use GbaseExec;

#权限需求：
#CONNECT权限
#SHOW DATABASES权限
#replication client权限
#gbase库只读
#information_schema库只读

#配置进程的filter，下面是配置例子
#这里的匹配是通过命令行加上环境变量的文本进行初步筛选判断
#最终是否是需要的进程，还需要各个Collector自身进行增强性的判断，
#如果collect方法返回undef就代表不匹配
sub getConfig {
    return {
        regExps => ['\bgbased\b'],        #正则表达是匹配ps输出
        psAttrs => { COMM => 'gbased' }
    };
}

sub getUser {
    my ($self) = @_;

    my $gbase = $self->{gbase};
    my @users;
    my $rows = $gbase->query(
        sql     => q{select distinct user from gbase.user where user not in ('gbase.session','gbase.sys')},
        verbose => $self->{isVerbose}
    );

    # +------+
    # | user |
    # +------+
    # | root |
    my @users;
    foreach my $row (@$rows) {
        if ( $row->{user} ne '' ) {
            push( @users, $row->{user} );
        }
    }

    #TODO: How to get user default table space, 老的是有有问题的，没有迁移过来

    return \@users;
}

sub parseCommandOpts {
    my ( $self, $command, $procInfo ) = @_;

    my $opts       = {};
    my @items      = split( /[\s"]+--/, $command );
    my $gbasedPath = $items[0];
    $gbasedPath =~ s/^\s*|\s*$//g;
    $gbasedPath =~ s/^"|"$//g;

    #$gbasedPath =~ s/\\/\//g;

    if ( not -e $gbasedPath and not -e "$gbasedPath.exe" ) {
        my $exeFile = $procInfo->{EXECUTABLE_FILE};
        if ( defined($exeFile) ) {
            $gbasedPath = $exeFile;
        }
        else {
            my $pid   = $procInfo->{PID};
            my $utils = $self->{collectUtils};
            $gbasedPath = $utils->getExecutablePath($pid);
        }
    }

    $gbasedPath =~ s/\\/\//g;
    $opts->{gbasedPath} = $gbasedPath;
    if ( $gbasedPath =~ /^(.*?)[\/\\]bin[\/\\]gbased/ or $gbasedPath =~ /^(.*?)[\/\\]sbin[\/\\]gbased/ ) {
        $opts->{gbaseHome} = $1;
    }

    for ( my $i = 1 ; $i < scalar(@items) ; $i++ ) {
        my $item = $items[$i];
        my ( $key, $val ) = split( '=', $item );
        $opts->{$key} = $val;
    }

    if ( not defined( $opts->{gbaseHome} ) ) {
        $opts->{gbaseHome} = $opts->{basedir};
    }

    return $opts;
}

#可用参数：
#$self->{procInfo}， 根据config命中的进程信息
#$self->{matchedProcsInfo}，之前已经matched的进程信息
#Return：应用信息的Hash，undef:不匹配
sub collect {
    my ($self) = @_;

    $self->{isVerbose} = 1;

    #如果不是主进程，则不match，则返回null
    if ( not $self->isMainProcess() ) {
        return undef;
    }

    my $procInfo         = $self->{procInfo};
    my $connInfo         = $procInfo->{CONN_INFO};
    my $matchedProcsInfo = $self->{matchedProcsInfo};

    my $gbaseInfo = {};
    $gbaseInfo->{MGMT_IP}       = $procInfo->{MGMT_IP};
    $gbaseInfo->{_OBJ_CATEGORY} = CollectObjCat->get('DBINS');

    #设置此采集到的对象对象类型，可以是：CollectObjCat->get('INS')，CollectObjCat->get('DBINS')，CollectObjCat::OS

    my $osType     = $procInfo->{OS_TYPE};
    my $osUser     = $procInfo->{USER};
    my $command    = $procInfo->{COMMAND};
    my $opts       = $self->parseCommandOpts( $command, $procInfo );
    my $gbaseHome  = $opts->{gbaseHome};
    my $gbasedPath = $opts->{gbasedPath};

    if ( not -e $gbasedPath and not -e "$gbasedPath.exe" ) {
        print("ERROR: Gbase bin $gbasedPath not found.\n");
        return undef;
    }

    $gbaseInfo->{INSTALL_PATH}  = $gbaseHome;
    $gbaseInfo->{GBASE_BASE}    = $opts->{'basedir'};
    $gbaseInfo->{GBASE_DATADIR} = $opts->{'datadir'};
    $gbaseInfo->{ERROR_LOG}     = $opts->{'log-error'};
    $gbaseInfo->{SOCKET_PATH}   = $opts->{'socket'};

    if ( $opts->{'defaults-file'} ) {
        $gbaseInfo->{CONFIG_FILE} = $opts->{'defaults-file'};
    }
    else {
        $gbaseInfo->{CONFIG_FILE} = '/etc/my.cnf';
    }

    my ( $ports, $port ) = $self->getPortFromProcInfo($gbaseInfo);
    if ( defined( $opts->{'port'} ) and $opts->{'port'} ne '' ) {
        $port = int( $opts->{'port'} );
    }

    if ( $port == 65535 or $port == 0 ) {
        print("WARN: Can not determine Gbase listen port.\n");
        return undef;
    }

    my $pFinder = $self->{pFinder};
    my ( $bizIp, $vip ) = $pFinder->predictBizIp( $connInfo, $port );

    $gbaseInfo->{PRIMARY_IP}     = $bizIp;
    $gbaseInfo->{VIP}            = $vip;
    $gbaseInfo->{PORT}           = $port;
    $gbaseInfo->{SERVICE_ADDR}   = "$vip:$port";
    $gbaseInfo->{SSL_PORT}       = undef;
    $gbaseInfo->{ADMIN_PORT}     = $port;
    $gbaseInfo->{ADMIN_SSL_PORT} = undef;

    my ( $helpRet, $verOutLines ) = $self->getCmdOutLines( qq{"$gbasedPath" --help}, $osUser );
    if ( $helpRet ne 0 ) {
        $verOutLines = $self->getCmdOutLines(qq{"$gbasedPath" --help});
    }
    my $version;
    foreach my $line (@$verOutLines) {
        if ( $line =~ /\bgbased\s+(.*?)$/s ) {
            $version = $1;
            last;
        }
    }
    $gbaseInfo->{VERSION} = $version;
    if ( $version =~ /(\d+)/ ) {
        $gbaseInfo->{MAJOR_VERSION} = "Gbase$1";
    }

    my $host  = $bizIp;
    my $gbase = GbaseExec->new(
        gbaseHome => $gbaseHome,
        username  => $self->{defaultUsername},
        password  => $self->{defaultPassword},
        host      => $host,
        port      => $port
    );
    $self->{gbase} = $gbase;

    my $rows;
    $rows = $gbase->query(
        sql     => 'show databases;',
        verbose => $self->{isVerbose}
    );

    # +-------------------------+
    # | Database                |
    # +-------------------------+
    # | ApolloConfigDB          |
    # | asmv3                   |
    my @dbNames = ();
    foreach my $row (@$rows) {
        my $dbName = $row->{Database};
        if ( $dbName ne 'information_schema' and $dbName ne 'gbase' and $dbName ne 'performance_schema' and $dbName ne 'gctmpdb' and $dbName ne 'gclusterdb' ) {
            push( @dbNames, $dbName );
        }
    }

    #$gbaseInfo->{DATABASES} = \@dbNames;

    $rows = $gbase->query(
        sql     => q{select * from information_schema.schemata},
        verbose => $self->{isVerbose}
    );

    # +--------------+-------------------------+----------------------------+------------------------+----------+
    # | CATALOG_NAME | SCHEMA_NAME             | DEFAULT_CHARACTER_SET_NAME | DEFAULT_COLLATION_NAME | SQL_PATH |
    # +--------------+-------------------------+----------------------------+------------------------+----------+
    # | def          | ApolloConfigDB          | utf8                       | utf8_bin               | NULL     |
    # | def          | ApolloPortalDB          | utf8                       | utf8_bin               | NULL     |

    my $dbCharsetInfo = {};
    foreach my $row (@$rows) {
        my $dbInfo = {};
        $dbInfo->{_OBJ_CATEGORY}                = CollectObjCat->get('DB');
        $dbInfo->{_OBJ_TYPE}                    = 'Gbase-DB';
        $dbInfo->{NAME}                         = $row->{SCHEMA_NAME};
        $dbInfo->{DEFAULT_CHARACTER_SET}        = $row->{DEFAULT_CHARACTER_SET_NAME};
        $dbInfo->{DEFAULT_COLLATION}            = $row->{DEFAULT_COLLATION_NAME};
        $dbInfo->{PRIMARY_IP}                   = $bizIp;
        $dbInfo->{VIP}                          = $vip;
        $dbInfo->{PORT}                         = $port;
        $dbInfo->{SSL_PORT}                     = undef;
        $dbInfo->{SERVICE_ADDR}                 = "$vip:$port";
        $dbCharsetInfo->{ $row->{SCHEMA_NAME} } = $dbInfo;
        $dbInfo->{INSTANCES}                    = [
            {
                _OBJ_CATEGORY => CollectObjCat->get('DBINS'),
                _OBJ_TYPE     => 'Gbase',
                INSTANCE_NAME => $procInfo->{HOST_NAME},
                MGMT_IP       => $gbaseInfo->{MGMT_IP},
                PORT          => $port
            }
        ];
    }

    my @dbInfos = ();
    foreach my $dbName (@dbNames) {
        push( @dbInfos, $dbCharsetInfo->{$dbName} );
    }
    $gbaseInfo->{DATABASES} = \@dbInfos;

    #收集集群相关的信息
    my $nodeOutput = `gcadmin showcluster d`;

    # CLUSTER STATE:         ACTIVE
    # VIRTUAL CLUSTER MODE:  NORMAL
    # 
    # =========================================================================================================
    # |                                    GBASE DATA CLUSTER INFORMATION                                     |
    # =========================================================================================================
    # | NodeName |                IpAddress                 | DistributionId | gnode | syncserver | DataState |
    # ---------------------------------------------------------------------------------------------------------
    # |  node1   |              192.168.0.100               |       1        | OPEN  |    OPEN    |     0     |
    # ---------------------------------------------------------------------------------------------------------
	
	my @clusterRoles = ();
	if (index($nodeOutput, $bizIp) != -1) {
		push( @clusterRoles, "dataNode");
	}
    my @lines = split /\n/, $nodeOutput;

    #根据正则匹配每一行数据是否有ip信息，判断有多少个节点，只有一个节点就认为是单节点运行。集群模式还不知道怎么判断。
    my @ip_lines = grep { /\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/ } @lines;
    my $data_lines = @ip_lines;
    if ($data_lines == 1) {
    	$gbaseInfo->{'IS_CLUSTER'} = 0;
        $gbaseInfo->{'CLUSTER_MODE'} = undef;
        $gbaseInfo->{'CLUSTER_ROLE'} = undef;
    }
	elsif ($data_lines > 1) {
    	$gbaseInfo->{'IS_CLUSTER'} = 1;
    }


    my $coordCmd = "gcadmin showcluster c|grep " . $bizIp;
	
	# CLUSTER STATE:         ACTIVE
	# CLUSTER MODE:          NORMAL
	# 
	# =======================================================
	# |        GBASE COORDINATOR CLUSTER INFORMATION        |
	# =======================================================
	# |   NodeName   |   IpAddress   | gcluster | DataState |
	# -------------------------------------------------------
	# | coordinator1 | 192.168.0.100 |   OPEN   |     0     |
	# -------------------------------------------------------
	
	my $coordOutput = `$coordCmd`;
	if ($coordOutput ne '') {
		push( @clusterRoles, "coordinator");
	}

	my $gcwareCmd = "gcadmin showcluster g|grep " . $bizIp;
	
	# CLUSTER STATE:         ACTIVE
	# VIRTUAL CLUSTER MODE:  NORMAL
	# 
	# =====================================
	# | GBASE GCWARE CLUSTER INFORMATION  |
	# =====================================
	# | NodeName |   IpAddress   | gcware |
	# -------------------------------------
	# | gcware1  | 192.168.0.100 |  OPEN  |
	# -------------------------------------
	
	my $gcwareOutput = `$gcwareCmd`;
	if ($gcwareOutput ne '') {
		push( @clusterRoles, "gcware");
	}
    $gbaseInfo->{'CLUSTER_ROLE'} = \@clusterRoles;

    $rows = $gbase->query(
        sql     => 'show global variables;',
        verbose => $self->{isVerbose}
    );
    my $variables = {};
    foreach my $row (@$rows) {
        $variables->{ $row->{Variable_name} } = $row->{Value};
    }
    map { $gbaseInfo->{ uc($_) } = $variables->{$_} } ( keys(%$variables) );
    $gbaseInfo->{SYSTEM_CHARSET} = $variables->{character_set_database};

    #服务名, 要根据实际来设置
    $gbaseInfo->{SERVER_NAME}   = $procInfo->{HOST_NAME};
    $gbaseInfo->{INSTANCE_NAME} = $procInfo->{HOST_NAME};

    my @collectSet = ();
    push( @collectSet, $gbaseInfo );
    push( @collectSet, @{ $gbaseInfo->{DATABASES} } );
    return @collectSet;
}

1;
