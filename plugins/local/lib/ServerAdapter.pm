#!/usr/bin/perl
use strict;
use FindBin;

package ServerAdapter;
use JSON;
use Cwd;
use Config::Tiny;

use DeployUtils;
use Data::Dumper;

sub new {
    my ( $pkg, %args ) = @_;

    my $self = {};

    if ( $ENV{AUTOEXEC_DEV_MODE} ) {
        $self->{devMode} = 1;
    }

    my $deployUtils = DeployUtils->new();
    $self->{DeployUtils} = $deployUtils;

    bless( $self, $pkg );
    return $self;
}

sub getIdPath {
    my ( $self, $namePath ) = @_;

    #-----------------------
    #getIdPath
    #in:  $namePath  Operate enviroment path, example:mysys/mymodule/SIT
    #ret: idPath of operate enviroment, example:100/200/3
    #-----------------------
    $namePath =~ s/^\/+|\/+$//g;
    my @dpNames = split( '/', $namePath );

    my $param = {};
    my $idx   = 0;
    for my $level ( 'sysName', 'moduleName', 'envName' ) {
        $param->{$level} = @dpNames[$idx];
        $idx = $idx + 1;
    }

    #TODO: call api convert namePath to idPath

    my $idPath = '0/0/0';    #测试用数据
    return $idPath;
}

sub getVer {
    my ( $self, $buildEnv, $version, $buildNo ) = @_;

    #获取版本详细信息：repoType, repo, branch, tag, tagsDir, lastBuildNo, isFreeze, startRev, endRev
    #startRev: 如果是新版本，则获取同一个仓库地址和分支的所有版本最老的一次build的startRev
    #               如果是现有的版本，则获取当前版本的startRev
    #               如果获取不到则默认是0
    my $param = {
        sysId    => $buildEnv->{SYS_ID},
        subSysId => $buildEnv->{MODULE_ID},
        version  => $buildEnv->{VERSION},
        buildNo  => $buildEnv->{BUILD_NO}
    };

    if ( defined($version) and $version ne '' ) {
        $param->{version} = $version;
    }
    if ( defined($buildNo) and $buildNo ne '' ) {
        $param->{buildNo} = $buildNo;
    }

    #TODO: call api get verInfo by param
    my $verInfo     = {};
    my $lastBuildNo = $verInfo->{lastBuildNo};

    my $gitVerInfo = {
        version  => $buildEnv->{VERSION},
        buildNo  => $buildEnv->{BUILD_NO},
        repoType => 'GIT',
        repo     => 'http://192.168.0.82:7070/luoyu/webTest.git',
        trunk    => 'master',
        branch   => '2.0.0',
        tag      => '',
        tagsDir  => undef,
        isFreeze => 0,
        startRev => 'bda9fb6f',
        endRev   => 'f2a9c727',
    };

    my $svnVerInfo = {
        version  => $buildEnv->{VERSION},
        buildNo  => $buildEnv->{BUILD_NO},
        repoType => 'SVN',
        repo     => 'svn://192.168.0.88/webTest',
        trunk    => 'trunk',
        branch   => 'branches/1.0.0',
        tag      => undef,
        tagsDir  => 'tags',
        isFreeze => 0,
        startRev => '0',
        endRev   => '32',
    };

    my $verInfo = $gitVerInfo;
    return $verInfo;
}

sub updateVer {
    my ( $self, $buildEnv, $verInfo ) = @_;

    #getver之后update版本信息，更新版本的相关属性
    #repoType, repo, trunk, branch, tag, tagsDir, buildNo, isFreeze, startRev, endRev
    #TODO: 通过接口更新版本信息

    return;
}

sub releaseVer {
    my ( $self, $buildEnv, $version, $buildNo ) = @_;

    #更新某个version的buildNo的release状态为1，build成功
    #TODO: 发布版本，更新版本某个buildNo的release的状态为1
    return;
}

sub getAutoCfgConf {
    my ( $self, $buildEnv ) = @_;
    my $autoCfgMap = {};

    #TODO: autocfg配置的获取，获取环境和实例的autocfg的配置存放到buildEnv之中传递给autocfg程序

    $autoCfgMap = {
        autoCfg => {
            key1 => 'value1',
            key2 => 'value2'
        },
        insCfgList => [
            {
                insName => "insName1",
                autoCfg => {
                    key1 => 'value1',
                    key2 => 'value2'
                }
            },
            {
                insName => "insName2",
                autoCfg => {
                    key1 => 'value1',
                    key2 => 'value2'
                }
            }
        ]
    };
    return $autoCfgMap;
}

sub getDBConf {
    my ( $self, $buildEnv ) = @_;
    my $dbInfo = {};

    #TODO: dbConf配置的获取，获取环境下的DB的IP端口用户密码等配置信息
    my $dbConf = {
        'mydb.myuser' => {
            node => {
                resourceId     => 9823748347,
                nodeName       => 'bsm',
                accessEndpoint => '192.168.0.26:3306',
                nodeType       => 'Mysql',
                host           => '192.168.0.26',
                port           => 3306,
                username       => 'root',
                password       => '{ENCRYPTED}05a90b9d7fcd2449928041'
            },
            args => {
                locale            => 'en_US.UTF-8',
                fileCharset       => 'UTF-8',
                autocommit        => 0,
                dbVersion         => '10.3',
                dbArgs            => '',
                ignoreErrors      => 'ORA-403',
                dbaRole           => undef,           #DBA角色，如果只允许DBA操作SQL执行才需要设置这个角色名
                oraWallet         => '',              #只有oracle需要
                db2SqlTerminator  => '',              #只有DB2需要
                db2ProcTerminator => ''               #只有DB2需要
            }
        }
    };

    while ( my ( $schema, $conf ) = each(%$dbConf) ) {
        my $nodeInfo = $conf->{node};
        my $password = $nodeInfo->{password};
        if ( defined($password) and $password =~ s/^\{ENCRYPTED\}// ) {
            $nodeInfo->{password} = DeployUtils->_rc4_decrypt_hex( $DeployUtils::MY_KEY, $password );
        }
    }
    return $dbConf;
}

sub addBuildQuality {
    my ( $self, $buildEnv, $measures ) = @_;

    #TODO: 提交sonarqube扫描结果数据到后台，老版本有相应的实现
}

sub getAppPassWord {
    my ( $self, $buildEnv, $appUrl, $userName ) = @_;

    #TODO: 譬如F5、A10、DNS服务等API的密码
}

sub getSqlFileStatuses {
    my ( $self, $jobId, $deployEnv ) = @_;
    if ( defined($deployEnv) ) {

        #TODO:获取应用发布某个环境的所有的SQL状态List
    }
    else {
        #TODO:获取某个作业的所有的SQL状态List
    }

    #格式：
    my $sqlInfoList = [

        # {
        #     resourceId     => $nodeInfo->{resourceId},
        #     nodeName       => $nodeInfo->{nodeName},
        #     host           => $nodeInfo->{host},
        #     port           => $nodeInfo->{port},
        #     accessEndpoint => $nodeInfo->{accessEndpoint},
        #     sqlFile        => $sqlFile,
        #     status         => $preStatus,
        #     md5            => $md5Sum
        # },
        # {
        #     resourceId     => $nodeInfo->{resourceId},
        #     nodeName       => $nodeInfo->{nodeName},
        #     host           => $nodeInfo->{host},
        #     port           => $nodeInfo->{port},
        #     accessEndpoint => $nodeInfo->{accessEndpoint},
        #     sqlFile        => $sqlFile,
        #     status         => $preStatus,
        #     md5            => $md5Sum
        # }
    ];

    return $sqlInfoList;
}

sub checkInSqlFiles {
    my ( $self, $jobId, $sqlInfo, $deployEnv ) = @_;

    #$sqlInfoList格式
    #服务端接受到次信息，只需要增加不存在的SQL记录即可，已经存在的不需要更新
    # [
    #     {
    #         resourceId     => $nodeInfo->{resourceId},
    #         nodeName       => $nodeInfo->{nodeName},
    #         host           => $nodeInfo->{host},
    #         port           => $nodeInfo->{port},
    #         accessEndpoint => $nodeInfo->{accessEndpoint},
    #         sqlFile        => $sqlFile,
    #         status         => $preStatus,
    #         md5            => $md5Sum
    #     },
    #     {
    #         resourceId     => $nodeInfo->{resourceId},
    #         nodeName       => $nodeInfo->{nodeName},
    #         host           => $nodeInfo->{host},
    #         port           => $nodeInfo->{port},
    #         accessEndpoint => $nodeInfo->{accessEndpoint},
    #         sqlFile        => $sqlFile,
    #         status         => $preStatus,
    #         md5            => $md5Sum
    #     }
    # ]

    #TODO: 保存sql文件信息到DB，工具sqlimport、dpsqlimport调用此接口

    print Dumper ($sqlInfo);

    return;
}

sub pushSqlStatus {
    my ( $self, $jobId, $sqlFilesStatus, $deployEnv ) = @_;

    #$jobId: 324234
    #$sqlInfo = {
    #     jobId          => 83743,
    #     resourceId     => 243253234,
    #     nodeId         => 234324,
    #     nodeName       => 'mydb',
    #     host           => '192.168.0.2',
    #     port           => 3306,
    #     accessEndpoint => '192.168.0.2:3306',
    #     sqlFile        => 'mydb.myuser/1.test.sql',
    #     status         => 'success'
    # };
    #deployEnv: 包含SYS_ID、MODULE_ID、ENV_ID等环境的属性

    #TODO: 更新单个SQL状态的服务端接口对接（SQLFileStatus.pm调用此接口）
    print("DEBUG: update sql status to server.\n");
    print Dumper($sqlFilesStatus);
    return;
}

sub getBuild {
    my ( $self, $deployEnv, $version, $buildNo ) = @_;

    #download某个版本某个buildNo的版本制品到当前节点
    return;
}

1;
