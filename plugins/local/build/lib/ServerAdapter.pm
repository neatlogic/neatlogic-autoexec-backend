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

    #TODO: vcall api convert namePath to idPath

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

    return;
}

sub releaseVer {
    my ( $self, $buildEnv, $version, $buildNo ) = @_;

    #更新某个version的buildNo的release状态为1，build成功
    return;
}

sub getAutoCfgConf {
    my ( $self, $buildEnv ) = @_;

    #TODO: autocfg配置的获取，获取环境和实例的autocfg的配置存放到buildEnv之中传递给autocfg程序
    my $autoCfgMap = {
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
    ###############################
    if ( not defined($autoCfgMap) ) {
        $autoCfgMap = {};
    }
    return $autoCfgMap;
}
1;
