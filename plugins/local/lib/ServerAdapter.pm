#!/usr/bin/perl
use strict;

package ServerAdapter;

use FindBin;
use feature 'state';
use JSON;
use Cwd;
use Config::Tiny;
use MIME::Base64;
use Fcntl qw(:flock O_RDWR O_CREAT O_SYNC);
use Digest::SHA qw(hmac_sha256_hex);
use MIME::Base64;
use File::Path;

use WebCtl;
use ServerConf;
use DeployLock;
use Data::Dumper;

sub new {
    my ($pkg) = @_;

    state $instance;
    if ( !defined($instance) ) {
        my $self = {};
        $instance = bless( $self, $pkg );

        if ( $ENV{AUTOEXEC_DEV_MODE} ) {
            $self->{devMode} = 1;
        }

        my $serverConf = ServerConf->new();
        $self->{serverConf} = $serverConf;

        $self->{apiMap} = {
            'getIdPath' => '/codedriver/api/rest/resourcecenter/resource/sysidmoduleidenvid/get',

            #版本状态：pending|compiling|compiled|compile-failed|releasing|release-failed|released
            'getVer'             => '/codedriver/api/rest/deploy/version/info/get/forautoexec',
            'updateVer'          => '/codedriver/api/rest/deploy/version/info/update/forautoexec',
            'delBuild'           => '/codedriver/api/rest/deploy/version/buildNo/delete',
            'delVer'             => '/codedriver/api/rest/deploy/version/delete',
            'releaseVerToEnv'    => '/codedriver/api/rest/deploy/version/env/update/forautoexec',
            'getEnvVer'          => '/codedriver/api/rest/deploy/version/env/get/forautoexec',
            'getOtherSiteEnvVer' => '/codedriver/api/rest/deploy/version/env/get/forautoexec',

            #autocfg和DB配置自动生成
            'addAutoCfgKeys' => '',
            'addDBSchemas'   => '',

            #环境制品状态：pending|succeed｜failed
            'getAccountPwd'         => '/codedriver/api/rest/resourcecenter/resource/account/get',
            'getAutoCfgConf'        => '/codedriver/api/rest/deploy/app/env/all/autoconfig/get',
            'getDBConf'             => '/codedriver/api/rest/deploy/app/config/env/db/config/get/forautoexec',
            'addBuildQuality'       => '/codedriver/api/rest/deploy/versoin/build/quality/save',
            'getAppPassWord'        => '/codedriver/api/rest/resourcecenter/resource/account/get',
            'getSqlFileStatuses'    => '/codedriver/api/rest/autoexec/job/sql/list',
            'checkInSqlFiles'       => '/codedriver/api/rest/autoexec/job/sql/checkin',
            'pushSqlStatus'         => '/codedriver/api/rest/autoexec/job/sql/update',
            'updatePhaseStatus'     => '/codedriver/api/rest/autoexec/job/phase/status/update',
            'createJob'             => '/codedriver/api/rest/deploy/job/create',
            'getJobStatus'          => '/codedriver/api/rest/autoexec/job/status/get',
            'saveVersionDependency' => '/codedriver/api/rest/deploy/versoin/dependency/save/forautoexec',
            'setEnvVersion'         => '/codedriver/api/rest/deploy/env/version/save',
            'rollbackEnvVersion'    => '/codedriver/api/rest/deploy/env/version/rollback',
            'setInsVersion'         => '/codedriver/api/rest/deploy/instance/version/save',
            'rollbackInsVersion'    => '/codedriver/api/rest/deploy/instance/version/rollback',
            'getBuild'              => '/codedriver/api/binary/deploy/appbuild/download'
        };

        my $username    = $serverConf->{username};
        my $password    = $serverConf->{password};
        my $signHandler = sub {
            my ( $client, $uri, $postBody ) = @_;
            my $signContent = "$username#$uri#";
            if ( defined($postBody) ) {
                $signContent = $signContent . MIME::Base64::encode( $postBody, '' );
            }

            my $digest = 'Hmac ' . hmac_sha256_hex( $signContent, $password );
            $client->addHeader( 'Authorization', $digest );
            $client->addHeader( 'x-access-key',  $username );
        };

        $self->{signHandler} = $signHandler;
        my $webCtl = WebCtl->new($signHandler);

        $webCtl->setHeaders( { Tenant => $ENV{AUTOEXEC_TENANT}, authType => 'hmac' } );

        $self->{webCtl} = $webCtl;
    }

    return $instance;
}

sub _getApiUrl {
    my ( $self, $apiName ) = @_;
    my $url = $self->{serverConf}->{baseurl} . $self->{apiMap}->{$apiName};

    return $url;
}

sub _getParams {
    my ( $self, $buildEnv ) = @_;

    my $params = {
        runnerId    => $ENV{RUNNER_ID},
        runnerGroup => $buildEnv->{RUNNER_GROUP},
        jobId       => $ENV{AUTOEXEC_JOBID},
        phaseName   => $ENV{AUTOEXEC_PHASE_NAME},
        sysId       => $buildEnv->{SYS_ID},
        moduleId    => $buildEnv->{MODULE_ID},
        envId       => $buildEnv->{ENV_ID},
        namePath    => $buildEnv->{NAME_PATH},
        sysName     => $buildEnv->{SYS_NAME},
        moduleName  => $buildEnv->{MODULE_NAME},
        envName     => $buildEnv->{ENV_NAME},
        version     => $buildEnv->{VERSION},
        buildNo     => $buildEnv->{BUILD_NO}
    };

    return $params;
}

sub _getReturn {
    my ( $self, $content ) = @_;

    my $rcJson = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( 'ERROR: ' . $rcJson->{Message} );
    }

    return $rcObj;
}

sub getIdPath {
    my ( $self, $namePath ) = @_;

    #-----------------------
    #getIdPath
    #in:  $namePath  Operate enviroment path, example:mysys/mymodule/SIT
    #ret: idPath of operate enviroment, example:100/200/3
    #-----------------------

    $namePath =~ s/^\/+|\/+$//g;
    my @dpNames   = split( '/', $namePath );
    my @partsName = ( 'sysName', 'moduleName', 'envName' );

    my $param = {};
    my $len   = scalar(@dpNames);
    for ( my $idx = 0 ; $idx < $len ; $idx++ ) {
        $param->{ $partsName[$idx] } = $dpNames[$idx];
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getIdPath');
    my $content = $webCtl->postJson( $url, $param );
    my $rcObj   = $self->_getReturn($content);

    my $sysId    = $rcObj->{sysId};
    my $moduleId = $rcObj->{moduleId};
    my $envId    = $rcObj->{envId};
    my $idPath   = "$sysId/$moduleId";
    if ( defined($envId) and $envId ne '' ) {
        $idPath = "$idPath/$envId";
    }

    return $idPath;
}

sub getVer {
    my ( $self, $buildEnv, $version, $buildNo ) = @_;

    #获取版本详细信息：repoType, repo, branch, tag, tagsDir, lastBuildNo, isFreeze, startRev, endRev
    #startRev: 如果是新版本，则获取同一个仓库地址和分支的所有版本最老的一次build的startRev
    #               如果是现有的版本，则获取当前版本的startRev
    #               如果获取不到则默认是0

    #TODO: check call api get verInfo by param
    #my $verInfo;

    #TODO: Delete follow test lines
    # my $gitVerInfo = {
    #     version  => $buildEnv->{VERSION},
    #     buildNo  => $buildEnv->{BUILD_NO},
    #     repoType => 'GIT',
    #     repo     => 'http://192.168.0.82:7070/luoyu/webTest.git',
    #     trunk    => 'master',
    #     branch   => '2.0.0',
    #     tag      => '',
    #     tagsDir  => undef,
    #     isFreeze => 0,
    #     startRev => 'bda9fb6f',
    #     endRev   => 'f2a9c727',
    #     status   => 'released'
    # };

    # my $svnVerInfo = {
    #     version  => $buildEnv->{VERSION},
    #     buildNo  => $buildEnv->{BUILD_NO},
    #     repoType => 'SVN',
    #     repo     => 'svn://192.168.0.88/webTest',
    #     trunk    => 'trunk',
    #     branch   => 'branches/1.0.0',
    #     tag      => undef,
    #     tagsDir  => 'tags',
    #     isFreeze => 0,
    #     startRev => '0',
    #     endRev   => '32',
    #     status   => 'released'
    # };

    # my $verInfo = $gitVerInfo;
    # return $verInfo;

    #TODO: test data ended###########################

    my $param = $self->_getParams($buildEnv);

    if ( defined($version) and $version ne '' ) {
        $param->{version} = $version;
    }
    if ( defined($buildNo) and $buildNo ne '' ) {
        $param->{buildNo} = $buildNo;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getVer');
    my $content = $webCtl->postJson( $url, $param );
    my $rcObj   = $self->_getReturn($content);

    return $rcObj;
}

sub updateVer {
    my ( $self, $buildEnv, $verInfo ) = @_;

    #TODO: uncomment after test
    #return;

    #Test end########################

    #getver之后update版本信息，更新版本的相关属性
    #repoType, repo, trunk, branch, tag, tagsDir, buildNo, isFreeze, startRev, endRev
    my $params = $self->_getParams($buildEnv);

    my $uptVerInfo = {};
    while ( my ( $key, $val ) = each(%$verInfo) ) {
        if ( $key eq 'version' ) {
            $params->{version} = $val;
        }
        elsif ( $key eq 'buildNo' ) {
            if ( defined($val) and $val ne '' ) {
                $params->{buildNo} = $val;
            }
        }
        elsif ( $key ne 'password' ) {
            $uptVerInfo->{$key} = $val;
        }
    }

    $params->{verInfo} = $uptVerInfo;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('updateVer');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    #TODO: 测试通过接口更新版本信息

    return;
}

sub delVer {
    my ( $self, $buildEnv, $version ) = @_;

    #getver之后update版本信息，更新版本的相关属性
    #repoType, repo, trunk, branch, tag, tagsDir, buildNo, isFreeze, startRev, endRev
    my $params = $self->_getParams($buildEnv);
    $params->{version} = $version;
    $params->{buildNo} = 0;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('delVer');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    #TODO: 测试通过接口更新版本信息

    return;
}

sub delBuild {
    my ( $self, $buildEnv, $version, $buildNo ) = @_;

    #getver之后update版本信息，更新版本的相关属性
    #repoType, repo, trunk, branch, tag, tagsDir, buildNo, isFreeze, startRev, endRev
    my $params = $self->_getParams($buildEnv);
    $params->{version} = $version;
    $params->{buildNo} = $buildNo;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('delBuild');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    #TODO: 测试通过接口更新版本信息

    return;
}

sub releaseVerToEnv {
    my ( $self, $buildEnv, $status, $isMirror ) = @_;

    #更新某个version的buildNo的release状态为1，build成功
    my $params = $self->_getParams($buildEnv);

    #status: pending|released|release-failed
    $params->{status} = $status;
    if ( defined($isMirror) and $isMirror == 1 ) {
        $params->{isMirror} = 1;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('releaseVerToEnv');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    return;
}

sub getEnvVer {
    my ( $self, $deployEnv, $version ) = @_;

    #获取环境版本详细信息：version, buildNo, status
    my $param = $self->_getParams($deployEnv);

    if ( defined($version) and $version ne '' ) {
        $param->{version} = $version;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getEnvVer');
    my $content = $webCtl->postJson( $url, $param );
    my $rcObj   = $self->_getReturn($content);

    return $rcObj;
}

sub getOtherSiteEnvVer {
    my ( $self, $proxyToUrl, $buildEnv, $version ) = @_;

    #获取环境版本详细信息：version, buildNo, status
    my $param = $self->_getParams($buildEnv);

    if ( defined($version) and $version ne '' ) {
        $param->{version}    = $version;
        $param->{proxyToUrl} = $proxyToUrl;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getOtherSiteEnvVer');
    my $content = $webCtl->postJson( $url, $param );
    my $rcObj   = $self->_getReturn($content);

    return $rcObj;
}

sub addAutoCfgKeys {
    my ( $self, $deployEnv, $autoCfgKeys ) = @_;

    #remove after TEST
    return;
    ############

    if ( not defined($autoCfgKeys) or scalar(@$autoCfgKeys) == 0 ) {
        return;
    }

    my $param = $self->_getParams($deployEnv);
    $param->{autoCfgKeys} = $autoCfgKeys;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('addAutoCfgKeys');
    my $content = $webCtl->postJson( $url, $param );
    my $rcObj   = $self->_getReturn($content);

    return $rcObj;
}

sub addDBSchemas {
    my ( $self, $deployEnv, $dbSchemas ) = @_;

    #remove after TEST
    return;
    ############

    if ( not defined($dbSchemas) or scalar(@$dbSchemas) == 0 ) {
        return;
    }

    my $param = $self->_getParams($deployEnv);
    $param->{dbSchemas} = $dbSchemas;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('addDBSchemas');
    my $content = $webCtl->postJson( $url, $param );
    my $rcObj   = $self->_getReturn($content);

    return $rcObj;
}

sub getAutoCfgConf {
    my ( $self, $buildEnv ) = @_;

    #数据格式
    # {
    #     autoCfg => {
    #         key1 => 'value1',
    #         key2 => 'value2'
    #     },
    #     insCfgList => [
    #         {
    #             insName => "insName1",
    #             autoCfg => {
    #                 key1 => 'value1',
    #                 key2 => 'value2'
    #             }
    #         },
    #         {
    #             insName => "insName2",
    #             autoCfg => {
    #                 key1 => 'value1',
    #                 key2 => 'value2'
    #             }
    #         }
    #     ]
    # };

    my $params = $self->_getParams($buildEnv);

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getAutoCfgConf');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    my $autoCfgMap = $rcObj;

    return $autoCfgMap;
}

sub getDBConf {
    my ( $self, $buildEnv ) = @_;

    #数据格式
    # {
    #     'mydb.myuser' => {
    #         node => {
    #             resourceId     => 9823748347,
    #             nodeName       => 'bsm',
    #             serviceAddr => '192.168.0.26:3306',
    #             nodeType       => 'Mysql',
    #             host           => '192.168.0.26',
    #             port           => 3306,
    #             username       => 'root',
    #             password       => '{ENCRYPTED}05a90b9d7fcd2449928041'
    #         },
    #         args => {
    #             locale            => 'en_US.UTF-8',
    #             fileCharset       => 'UTF-8',
    #             autocommit        => 0,
    #             dbVersion         => '10.3',
    #             dbArgs            => '',
    #             ignoreErrors      => 'ORA-403',
    #             dbaRole           => undef,           #DBA角色，如果只允许DBA操作SQL执行才需要设置这个角色名
    #             oraWallet         => '',              #只有oracle需要
    #             db2SqlTerminator  => '',              #只有DB2需要
    #             db2ProcTerminator => ''               #只有DB2需要
    #         }
    #     }
    # };

    my $params = $self->_getParams($buildEnv);

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getDBConf');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    my $dbConf     = $rcObj;
    my $serverConf = $self->{serverConf};
    while ( my ( $schema, $conf ) = each(%$dbConf) ) {
        my $nodeInfo = $conf->{node};
        my $password = $nodeInfo->{password};
        if ( defined($password) ) {
            $nodeInfo->{password} = $serverConf->decryptPwd($password);
        }
    }
    return $dbConf;
}

sub addBuildQuality {
    my ( $self, $buildEnv, $measures ) = @_;

    my $params = $self->_getParams($buildEnv);
    while ( my ( $key, $val ) = each(%$measures) ) {
        $params->{$key} = $val;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('addBuildQuality');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    #TODO: 测试 提交sonarqube扫描结果数据到后台，老版本有相应的实现
    return;
}

sub getAccountPwd {
    my ( $self, %args ) = @_;

    my $params = {
        jobId      => $args{jobId},
        resourceId => $args{resourceId},
        nodeName   => $args{nodeName},
        nodeType   => $args{nodeType},
        host       => $args{host},
        port       => $args{port},
        username   => $args{username},
        protocol   => $args{protocol},
        accountId  => $args{accountId}
    };

    my $webCtl     = $self->{webCtl};
    my $url        = $self->_getApiUrl('getAccountPwd');
    my $content    = $webCtl->postJson( $url, $params );
    my $pass       = $self->_getReturn($content);
    my $serverConf = $self->{serverConf};
    $pass = $serverConf->decryptPwd($pass);

    return $pass;
}

sub getAppPassWord {
    my ( $self, $buildEnv, $appUrl, $userName ) = @_;

    my $params = $self->_getParams($buildEnv);

    my $protocol;
    my $host;
    my $port;
    if ( $appUrl =~ /(http|https):\/\/(.*?)\/?/i ) {
        $protocol = lc($1);
        my $hostAndPort = $2;
        if ( $hostAndPort =~ /(.*?):(\d+)/ ) {
            $host = $1;
            $port = $2;
        }
        else {
            $host = $hostAndPort;
            if ( $protocol eq 'https' ) {
                $port = 443;
            }
            else {
                $port = 80;
            }
        }
    }

    $params->{protocol} = $protocol;
    $params->{host}     = $host;
    $params->{port}     = $port;
    $params->{username} = $userName;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getAppPassWord');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    my $pass        = 'notfound';
    my $accountList = $rcObj;
    if ( scalar(@$accountList) > 1 ) {
        my $accountInfo = $$accountList[0];
        $pass = $accountInfo->{password};
        my $serverConf = $self->{serverConf};
        $pass = $serverConf->decryptPwd($pass);
    }

    #TODO: check and test 譬如F5、A10、DNS服务等API的密码
    return $pass;
}

sub getSqlFileStatuses {
    my ( $self, $jobId, $deployEnv, $sqlFiles ) = @_;

    #返回数据格式
    # [
    # {
    #     resourceId     => $nodeInfo->{resourceId},
    #     serviceAddr => $nodeInfo->{serviceAddr},
    #     nodeType       => $nodeInfo->{nodeType},
    #     nodeName       => $nodeInfo->{nodeName},
    #     host           => $nodeInfo->{host},
    #     port           => $nodeInfo->{port},
    #     username       => $nodeInfo->{username},
    #     sqlFile        => $sqlFile,
    #     status         => $preStatus,
    #     md5            => $md5Sum
    # },
    # {
    #     resourceId     => $nodeInfo->{resourceId},
    #     serviceAddr => $nodeInfo->{serviceAddr},
    #     nodeType       => $nodeInfo->{nodeType},
    #     nodeName       => $nodeInfo->{nodeName},
    #     host           => $nodeInfo->{host},
    #     port           => $nodeInfo->{port},
    #     username       => $nodeInfo->{username},
    #     sqlFile        => $sqlFile,
    #     status         => $preStatus,
    #     md5            => $md5Sum
    # }
    #]

    my $params = {};

    if ( defined($deployEnv) ) {

        #获取应用发布某个环境的所有的SQL状态List
        $params = $self->_getParams($deployEnv);
        $params->{operType} = 'deploy';
    }
    else {
        #获取某个作业的所有的SQL状态List
        $params->{jobId}     = $jobId;
        $params->{runnerId}  = $ENV{RUNNER_ID};
        $params->{phaseName} = $ENV{AUTOEXEC_PHASE_NAME};
        $params->{operType}  = 'auto';
    }

    if ( defined($sqlFiles) ) {
        $params->{sqlFiles} = $sqlFiles;
    }
    else {
        $params->{sqlFiles} = undef;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getSqlFileStatuses');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    my $sqlInfoList = $rcObj;

    return $sqlInfoList;
}

sub checkInSqlFiles {
    my ( $self, $jobId, $targetPhase, $sqlInfoList, $deployEnv ) = @_;

    #$sqlInfoList格式
    #服务端接受到次信息，只需要增加不存在的SQL记录即可，已经存在的不需要更新
    # [
    #     {
    #         resourceId     => $nodeInfo->{resourceId},
    #         serviceAddr => $nodeInfo->{serviceAddr},
    #         nodeType       => $nodeInfo->{nodeType},
    #         nodeName       => $nodeInfo->{nodeName},
    #         host           => $nodeInfo->{host},
    #         port           => $nodeInfo->{port},
    #         username       => $nodeInfo->{username},
    #         sqlFile        => $sqlFile,
    #         status         => $preStatus,
    #         md5            => $md5Sum
    #     },
    #     {
    #         resourceId     => $nodeInfo->{resourceId},
    #         serviceAddr => $nodeInfo->{serviceAddr},
    #         nodeType       => $nodeInfo->{nodeType},
    #         nodeName       => $nodeInfo->{nodeName},
    #         host           => $nodeInfo->{host},
    #         port           => $nodeInfo->{port},
    #         username       => $nodeInfo->{username},
    #         sqlFile        => $sqlFile,
    #         status         => $preStatus,
    #         md5            => $md5Sum
    #     }
    # ]

    if ( not @$sqlInfoList ) {
        return;
    }

    my $params = {};
    if ( defined($deployEnv) ) {
        $params = $self->_getParams($deployEnv);
        $params->{operType} = 'deploy';
    }
    else {
        $params->{jobId}     = $jobId;
        $params->{runnerId}  = $ENV{RUNNER_ID};
        $params->{phaseName} = $ENV{AUTOEXEC_PHASE_NAME};
        $params->{operType}  = 'auto';
    }

    $params->{jobId}       = $jobId;
    $params->{sqlInfoList} = $sqlInfoList;

    if ( not defined($targetPhase) ) {
        $targetPhase = $params->{phaseName};
    }
    $params->{targetPhaseName} = $targetPhase;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('checkInSqlFiles');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    #TODO: 测试 保存sql文件信息到DB，工具sqlimport、dpsqlimport调用此接口

    return;
}

sub pushSqlStatus {
    my ( $self, $jobId, $sqlStatus, $deployEnv ) = @_;

    #$jobId: 324234
    #$sqlInfo = {
    #     jobId          => 83743,
    #     resourceId     => 243253234,
    #     nodeName       => 'mydb',
    #     host           => '192.168.0.2',
    #     port           => 3306,
    #     serviceAddr => '192.168.0.2:3306',
    #     sqlFile        => 'mydb.myuser/1.test.sql',
    #     status         => 'success'
    # };
    #deployEnv: 包含SYS_ID、MODULE_ID、ENV_ID等环境的属性
    if ( not $sqlStatus ) {
        return;
    }

    my $params = {};
    if ( defined($deployEnv) ) {
        $params = $self->_getParams($deployEnv);
        $params->{operType} = 'deploy';
    }
    else {
        $params->{jobId}     = $jobId;
        $params->{runnerId}  = $ENV{RUNNER_ID};
        $params->{phaseName} = $ENV{AUTOEXEC_PHASE_NAME};
        $params->{operType}  = 'auto';
    }

    $params->{jobId}     = $jobId;
    $params->{sqlStatus} = $sqlStatus;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('pushSqlStatus');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    return;
}

sub updatePhaseStatus {
    my ( $self, $jobId, $phaseStatus ) = @_;

    #$jobId: 324234
    # params = {
    #     'jobId': self.context.jobId,
    #     'groupNo': groupNo,
    #     'phase': phaseName,
    #     'status': phaseStatus,
    #     'passThroughEnv': self.context.passThroughEnv
    # }

    if ( not $phaseStatus ) {
        return;
    }

    my $passThroughEnv = {};
    if ( $ENV{PASSTHROUGH_ENV} ) {
        $passThroughEnv = from_json( $ENV{PASSTHROUGH_ENV} );
    }

    my $params = {
        jobId          => $jobId,
        groupNo        => $ENV{GROUP_NO},
        phase          => $ENV{AUTOEXEC_PHASE_NAME},
        status         => $phaseStatus,
        passThroughEnv => $passThroughEnv
    };

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('updatePhaseStatus');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    return;
}

sub createJob {
    my ( $self, $jobId, %args ) = @_;

    # %args说明
    # {
    #     name => 'xxxxx', #作业名
    #     version => 'xxxxx', #目标版本号
    #     nodeList => [{ip=>'xxxxx', port=>dddd}], #节点列表，默认空就是全部
    #     scenarioName => 'xxxxx', #场景名
    #     roudnCount => 2, #分组运行组的数量
    #     param => {key => 'value',....} #扩展参数
    # }

    my $params = {
        proxyToUrl => $args{proxyToUrl},
        parentId   => $jobId,
        execUser   => $args{execUser},
        source     => 'deploy',
        name       => $args{name},
        moduleList => [
            {
                name           => $args{moduleName},
                version        => $args{version},
                buildNo        => $args{buildNo},
                selectNodeList => $args{nodeList}
            }
        ],
        scenarioName  => $args{scenarioName},
        appSystemName => $args{sysName},
        envName       => $args{envName},
        roundCount    => $args{roundCount},
        planStartTime => $args{planStartTime},
        isRrunNow     => $args{isRunNow},
        param         => $args{param}
    };

    if ( $args{triggerType} ne 'now' ) {
        $params->{triggerType} = $args{triggerType};
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('createJob');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    my $chldJobId;
    if ( scalar(@$rcObj) > 0 ) {
        $chldJobId = $$rcObj[0]->{jobId};
        if ( not defined($chldJobId) ) {
            die( $$rcObj[0]->{errorMsg} . "\n" );
        }
    }

    return $chldJobId;
}

sub getJobStatus {
    my ( $self, $jobId, %args ) = @_;

    my $params = {
        jobId      => $jobId,
        proxyToUrl => $args{proxyToUrl}
    };

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getJobStatus');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    my $jobStatus = $rcObj->{status};

    return $jobStatus;
}

sub saveVersionDependency {
    my ( $self, $buildEnv, $data ) = @_;

    #TODO： save jar dependency infomations
    my $params = $self->_getParams($buildEnv);
    $params->{dependenceList} = $data;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('saveVersionDependency');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    return;
}

sub setEnvVersion {
    my ( $self, $deployEnv, $execUser, $epochTime ) = @_;

    my $params = $self->_getParams($deployEnv);
    $params->{execUser}   = $execUser;
    $params->{deployTime} = $epochTime;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('setEnvVersion');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    #TODO： Test plugin (tagenvver) set Env version
    return;
}

sub rollbackEnvVersion {
    my ( $self, $deployEnv, $execUser, $epochTime ) = @_;

    my $params = $self->_getParams($deployEnv);
    $params->{execUser}   = $execUser;
    $params->{deployTime} = $epochTime;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('rollbackEnvVersion');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    #TODO： Test plugin (tagenvver --rollback) test rollback env version
    return;
}

sub setInsVersion {
    my ( $self, $buildEnv, $nodeInfo, $execUser, $epochTime, $status ) = @_;

    my $params = $self->_getParams($buildEnv);
    $params->{resourceId} = $nodeInfo->{resourceId};
    $params->{execUser}   = $execUser;
    $params->{deployTime} = $epochTime;
    $params->{status}     = $status;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('setInsVersion');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    #TODO： Test plugin (taginsver) test set instance version
    return;
}

sub rollbackInsVersion {
    my ( $self, $buildEnv, $nodeInfo, $execUser, $epochTime, $status ) = @_;

    my $params = $self->_getParams($buildEnv);
    $params->{resourceId} = $nodeInfo->{resourceId};
    $params->{execUser}   = $execUser;
    $params->{deployTime} = $epochTime;
    $params->{status}     = $status;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('rollbackInsVersion');
    my $content = $webCtl->postJson( $url, $params );
    my $rcObj   = $self->_getReturn($content);

    #TODO： Test plugin (taginsver --rollback) test rollback instance version
    return;
}

sub getBuild {
    my ( $self, $deployUtils, $deployEnv, $buildNo, $proxyToUrl, $srcEnvInfo, $destDir, $subDirs, $cleanSubDirs ) = @_;

    #download某个版本某个buildNo的版本制品到当前节点
    my $params = $self->_getParams($deployEnv);
    my $pdata  = {
        namePath   => $params->{namePath},
        sysName    => $params->{sysName},
        moduleName => $params->{moduleName},
        envName    => $params->{envName},
        version    => $params->{version},
        buildNo    => $params->{buildNo},
        subDirs    => $subDirs,
        proxyToUrl => $proxyToUrl
    };

    #如果srcEnvInfo定义了相应的系统、模块、环境名则使用它为准
    if ($srcEnvInfo) {
        my $srcNamePath = $srcEnvInfo->{namePath};
        if ( defined($srcNamePath) ) {
            if ( $srcNamePath eq $deployEnv->{NAME_PATH} ) {
                print("WARN: No need to get resource from the same environment.\n");
                return;
            }
        }
        else {
            print("WARN: No need to get resource from the same environment.\n");
            return;
        }

        while ( my ( $key, $val ) = each(%$srcEnvInfo) ) {
            $pdata->{$key} = $val;
        }
    }

    my $checked    = 0;
    my $builded    = 0;
    my $buildLocal = 'false';

    my $namePath = $deployEnv->{DEPLOY_PATH};
    my $version  = $deployEnv->{VERSION};

    my $gzMagicNum  = "\x1f\x8b";
    my $tarMagicNum = "\x75\x73";
    my ( $pid, $reader, $writer, $relStatus, $envRelStatus, $isMirror, $contentDisposition, $magicNum, $firstChunk );
    my $callback = sub {
        my ( $chunk, $res ) = @_;
        if ( $checked == 0 ) {
            $checked = 1;
            if ( $res->code eq 200 ) {
                $buildNo            = $res->header('Build-No');
                $relStatus          = $res->header('Build-Status');
                $envRelStatus       = $res->header('Build-Env-Status');
                $buildLocal         = $res->header('Build-Local');
                $isMirror           = $res->header('isMirror');
                $contentDisposition = $res->header('Content-Disposition');

                if ( defined($buildNo) and $buildNo ne '' ) {
                    $self->updateVer( $deployEnv, { version => $version, buildNo => $buildNo, status => 'releasing' } );
                }

                print("INFO: Build-Status:$relStatus\n");
                print("INFO: Build-Env-Status:$envRelStatus\n");
                print("INFO: Build-Local:$buildLocal\n");

                if ( $relStatus eq 'released' and $envRelStatus eq 'released' ) {
                    if ( $buildLocal ne 'true' ) {
                        $builded = 1;
                    }

                    $deployEnv->{BUILD_NO} = $buildNo;
                    my $buildEnv = $deployEnv;

                    my $buildPath = $deployEnv->{BUILD_ROOT} . "/$buildNo";
                    $buildEnv->{BUILD_PATH} = $buildPath;

                    if ( not -e $buildPath ) {
                        if ( not mkpath($buildPath) ) {
                            die("ERROR: Can not create directory $buildPath, $!\n");
                        }
                    }
                    if ( defined($destDir) and $destDir ne '' ) {
                        $buildPath = Cwd::abs_path("$buildPath/$destDir");
                    }

                    #lockBuild
                    my $lock      = DeployLock->new($buildEnv);
                    my $buildLock = $lock->lockBuild($DeployLock::WRITE);

                    END {
                        local $?;
                        if ( defined($lock) ) {
                            $lock->unlockBuild($buildLock);
                        }
                    }

                    if ( $cleanSubDirs == 1 ) {
                        foreach my $subDir (@$subDirs) {
                            foreach my $dir ( glob("$buildPath/$subDir") ) {
                                if ( -e $dir ) {

                                    #print("INFO: clean dir:$dir\n");
                                    rmtree($dir) or die("ERROR: Remove $dir failed.\n");
                                }
                            }
                        }
                    }
                    else {
                        if ( -e $buildPath ) {
                            rmtree($buildPath) or die("ERROR: Remove $buildPath failed.\n");
                            mkdir($buildPath);
                        }
                    }

                    $magicNum = substr( $chunk, 0, 2 );
                    my $cmd = "| tar -C '$buildPath' -xf -";
                    if ( $contentDisposition =~ /\.gz"?$/ or $magicNum eq $gzMagicNum ) {
                        $cmd = "| tar -C '$buildPath' -xzf -";
                    }
                    $pid = open( $writer, $cmd ) or die("ERROR: Open tar cmd failed:$!");
                    binmode($writer);
                }
            }
            else {
                $buildNo = $res->header('Build-No');
            }
        }

        if ( $builded == 1 ) {
            if ( not defined($firstChunk) and $magicNum ne $gzMagicNum and $magicNum ne $tarMagicNum ) {
                $firstChunk = $chunk;
            }
            print $writer ($chunk);
            $writer->flush();
        }
    };

    my $client = REST::Client->new();
    $client->addHeader( 'Content-Type', 'application/json;charset=UTF-8' );
    $client->addHeader( 'Tenant',       $ENV{AUTOEXEC_TENANT} );
    $client->addHeader( 'authType',     'hmac' );

    my $url = $self->_getApiUrl('getBuild');

    my $paramsJson  = to_json($pdata);
    my $signHandler = $self->{signHandler};
    my $uri         = substr( $url, index( $url, '/', 8 ) );
    &$signHandler( $client, $uri, $paramsJson );

    $client->getUseragent()->ssl_opts( verify_hostname => 0 );
    $client->getUseragent()->ssl_opts( SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE );
    $client->getUseragent()->timeout(1200);

    $client->setFollow(1);
    $client->setContentFile( \&$callback );

    $client->POST( $url, $paramsJson );
    $relStatus = $client->responseHeader('Build-Status');

    my $untarCode = 0;
    if ( defined($writer) ) {
        $untarCode = 1;
        close($writer);
        $untarCode = $?;
    }

    if ( $client->responseCode() ne 200 ) {
        if ( defined($buildNo) and $buildNo ne '' ) {
            $self->updateVer( $deployEnv, { version => $version, buildNo => $buildNo, status => 'release-failed' } );
        }

        my $errMsg = $client->responseContent();
        if ( defined($relStatus) ) {
            die("ERROR: Get build namePath Version:$version build$buildNo failed with status:$relStatus, cause by:$errMsg\n");
        }
        else {
            die("ERROR: Get build namePath Version:$version build$buildNo failed, cause by:$errMsg\n");
        }
    }

    if ( $relStatus ne 'released' or $envRelStatus ne 'released' ) {

        my $namePath = $pdata->{namePath};
        if ( defined($buildNo) and $buildNo ne '' ) {
            $self->updateVer( $deployEnv, { version => $version, buildNo => $buildNo, status => 'release-failed' } );
        }

        my $errMsg = $client->responseContent();

        if ( defined($relStatus) and $relStatus ne '' ) {
            if ( $relStatus eq 'null' ) {
                die("ERROR: $namePath Version:$version\_build$buildNo not exists.\n");
            }
            else {
                die("ERROR: $namePath Version:$version\_build$buildNo in error status:$relStatus.\n");
            }
        }
        elsif ( defined($envRelStatus) and $envRelStatus ne '' ) {
            if ( $envRelStatus eq 'null' ) {
                die("ERROR: $namePath ENV artifact Version:$version not exists.\n");
            }
            else {
                die("ERROR: $namePath ENV artifact Version:$version in error status:$envRelStatus.\n");
            }
        }
        else {
            die("ERROR: Get resources failed: $errMsg\n");
        }
    }

    if ( $untarCode eq 0 ) {
        if ( defined($buildNo) and $buildNo ne '' ) {
            $self->updateVer( $deployEnv, { version => $version, buildNo => $buildNo, status => 'released' } );
        }
    }
    else {
        $self->updateVer( $deployEnv, { version => $version, buildNo => $buildNo, status => 'release-failed' } );
        die("ERROR: Get resources failed with status:$relStatus, build resource is empty or data corrupted because of network timeout problem.\n");
    }

    return ( $isMirror, $buildNo );
}

1;
