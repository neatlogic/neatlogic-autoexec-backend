#!/usr/bin/perl
use strict;

package ServerAdapter;

sub getIdPath {
    my ( $self, $namePath ) = @_;
    $namePath =~ s/^\/+|\/+$//g;
    my @dpNames = split( '/', $namePath );

    my $param = {};
    my $idx   = 0;
    for my $level ( 'sysName', 'moduleName', 'envName' ) {
        $param->{$level} = @dpNames[$idx];
        $idx = $idx + 1;
    }

    #TODO: call api convert namePath to idPath

    my $idPath = $namePath;
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
        version  => $version,
        buildNo  => $buildNo
    };

    #TODO: call api get verInfo by param
    my $verInfo     = {};
    my $lastBuildNo = $verInfo->{lastBuildNo};

    my $gitVerInfo = {
        version  => $version,
        buildNo  => $buildNo,
        repoType => 'GIT',
        repo     => 'http://192.168.0.82:7070/luoyu/webTest.git',
        trunk    => 'master',
        branch   => '2.0.0',
        tag      => 'V2.0.0',
        tagsDir  => undef,
        isFreeze => 0,
        startRev => 'bda9fb6f',
        endRev   => 'f2a9c727',
        username => 'wenhb',                                        #optional
        password => 'xxxxx'                                         #optional
    };

    my $svnVerInfo = {
        version  => $version,
        buildNo  => $buildNo,
        repoType => 'SVN',
        repo     => 'svn://192.168.0.88/webTest',
        trunk    => 'trunk',
        branch   => 'branches/1.0.0',
        tag      => undef,
        tagsDir  => 'tags',
        isFreeze => 0,
        startRev => '0',
        endRev   => '32',
        username => 'admin',                        #optional
        password => 'wen7831'                       #optional
    };

    my $verInfo = $svnVerInfo;
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
    #TODO：发布版本，更新版本某个buildNo的release的状态为1
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
        'dbname.dbuser' => {
            node => {
                resourceId     => 9823748347,
                nodeName       => 'bsmdb',
                accessEndpoint => '192.168.0.26:3306',
                nodeType       => 'Mysql',
                host           => '192.168.0.26',
                port           => 3306,
                username       => 'root',
                password       => '{RC4}xxxxx'
            },
            args => {
                locale       => 'en_US.UTF-8',
                fileCharset  => 'UTF-8',
                autocommit   => 0,
                dbVersion    => '10.3',
                dbArgs       => '',
                ignoreErrors => 'ORA-403',
                oraWallet    => ''
            }
        }
    };
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

sub saveSqlFilesStatus {
    my ( $self, $buildEnv, $sqlFilesStatus ) = @_;

    #$sqlFilesStatus格式
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

    #TODO: 保存sql文件信息到DB

    return;
}
1;
