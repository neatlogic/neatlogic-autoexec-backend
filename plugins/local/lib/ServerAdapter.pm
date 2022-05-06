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

use WebCtl;
use Serverconf;
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

        $self->{serverConf} = ServerConf->new();

        $self->{apiMap} = {
            'getIdPath'          => 'codedriver/public/api/rest/ezdeploy/path',
            'getVer'             => 'codedriver/public/api/rest/ezdeploy/version/get',
            'updateVer'          => 'codedriver/public/api/rest/ezdeploy/version/update',
            'releaseVer'         => 'codedriver/public/api/rest/ezdeploy/version/release',
            'getAutoCfgConf'     => 'codedriver/public/api/rest/ezdeploy/autocfg/get',
            'getDBConf'          => 'codedriver/public/api/rest/ezdeploy/dbconf/get',
            'addBuildQulity'     => 'codedriver/public/api/rest/ezdeploy/scan/add',
            'getAppPassWord'     => 'codedriver/public/api/rest/cmdb/password/get',
            'getSqlFileStatuses' => 'codedriver/public/api/rest/ezdeploy/sql/status/get',
            'checkInSqlFiles'    => 'codedriver/public/api/rest/ezdeploy/sql/status/checkin',
            'pushSqlStatus'      => 'codedriver/public/api/rest/ezdeploy/sql/status/push',
            'getBuild'           => 'codedriver/public/api/rest/ezdeploy/getbuild'
        };

        my $webCtl = WebCtl->new();
        $webCtl->setHeaders( { Authorization => $self->_getAuthToken() } );
        $self->{webCtl} = $webCtl;
    }

    return $instance;
}

sub _getAuthToken() {
    my ($self)     = @_;
    my $serverConf = $self->{serverConf};
    my $username   = $serverConf->{username};
    my $password   = $serverConf->{password};

    my $authToken = 'Basic ' . MIME::Base64::encode( $username . ':' . $password );
    return $authToken;
}

sub _getApiUrl {
    my ( $self, $apiName ) = @_;
    my $url = $self->{serverConf}->{baseurl} . '/' . $self->{apiMap}->{$apiName};

    return $url;
}

sub _getParams {
    my ( $self, $buildEnv ) = @_;

    my $params = {
        sysId      => $buildEnv->{SYS_ID},
        moduleId   => $buildEnv->{MODULE_ID},
        envId      => $buildEnv->{ENV_ID},
        sysName    => $buildEnv->{SYS_NAME},
        moduleName => $buildEnv->{MODULE_NAME},
        envName    => $buildEnv->{ENV_NAME},
        version    => $buildEnv->{VERSION},
        buildNo    => $buildEnv->{BUILD_NO}
    };

    return $params;
}

sub getIdPath {
    my ( $self, $namePath ) = @_;

    #-----------------------
    #getIdPath
    #in:  $namePath  Operate enviroment path, example:mysys/mymodule/SIT
    #ret: idPath of operate enviroment, example:100/200/3
    #-----------------------

    #TODO: Delete follow test line
    my $idPath = '0/0/0';    #测试用数据

    return $idPath;

    #Test end########################################

    #TODO: check call api convert namePath to idPath
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
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

    my $idPath = $rcObj->{idPath};
    return $idPath;
}

sub getVer {
    my ( $self, $buildEnv, $version, $buildNo ) = @_;

    #获取版本详细信息：repoType, repo, branch, tag, tagsDir, lastBuildNo, isFreeze, startRev, endRev
    #startRev: 如果是新版本，则获取同一个仓库地址和分支的所有版本最老的一次build的startRev
    #               如果是现有的版本，则获取当前版本的startRev
    #               如果获取不到则默认是0

    #TODO: check call api get verInfo by param
    my $verInfo;

    #TODO: Delete follow test lines
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
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

    return $rcObj;
}

sub updateVer {
    my ( $self, $buildEnv, $verInfo ) = @_;

    #TODO: uncomment after test
    return;

    #Test end########################

    #getver之后update版本信息，更新版本的相关属性
    #repoType, repo, trunk, branch, tag, tagsDir, buildNo, isFreeze, startRev, endRev
    my $params = $self->_getParams($buildEnv);
    while ( my ( $key, $val ) = each(%$verInfo) ) {
        $params->{$key} = $val;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('updateVer');
    my $content = $webCtl->postJson( $url, $params );
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

    #TODO: 测试通过接口更新版本信息

    return;
}

sub releaseVer {
    my ( $self, $buildEnv, $version, $buildNo ) = @_;

    #TODO: uncomment after test
    return;

    #Test end############################

    #更新某个version的buildNo的release状态为1，build成功
    my $params = $self->_getParams($buildEnv);
    if ( defined($version) and $version ne '' ) {
        $params->{version} = $version;
    }
    if ( defined($buildNo) and $buildNo ne '' ) {
        $params->{buildNo} = $buildNo;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('releaseVer');
    my $content = $webCtl->postJson( $url, $params );
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

    #TODO: 测试 发布版本，更新版本某个buildNo的release的状态为1
    return;
}

sub getAutoCfgConf {
    my ( $self, $buildEnv ) = @_;

    #TODO: delete follow test lines
    #TODO: autocfg配置的获取，获取环境和实例的autocfg的配置存放到buildEnv之中传递给autocfg程序

    my $autoCfgMap = {
        autoCfg => {
            basic    => 'mybasicval',
            password => 'mypasswd'
        },
        insCfgList => [
            {
                insName => "insName1",
                autoCfg => {
                    basic    => 'ins1-mybasicval',
                    password => 'ins1-mypasswd'
                }
            },
            {
                insName => "insName2",
                autoCfg => {
                    basic    => 'ins2-mybasicval',
                    password => 'ins2-mypasswd'
                }
            }
        ]
    };

    return $autoCfgMap;

    #TODO: test end###############################################33

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
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

    my $autoCfgMap = $rcObj;

    return $autoCfgMap;
}

sub getDBConf {
    my ( $self, $buildEnv ) = @_;

    #TODO: Delete follow test lines
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

    my $serverConf = $self->{serverConf};
    while ( my ( $schema, $conf ) = each(%$dbConf) ) {
        my $nodeInfo = $conf->{node};
        my $password = $nodeInfo->{password};
        if ( defined($password) ) {
            $nodeInfo->{password} = $serverConf->decryptPwd($password);
        }
    }
    return $dbConf;

    #TODO:Test end##################################3

    #数据格式
    # {
    #     'mydb.myuser' => {
    #         node => {
    #             resourceId     => 9823748347,
    #             nodeName       => 'bsm',
    #             accessEndpoint => '192.168.0.26:3306',
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
    my $url     = $self->_getApiUrl('getAutoCfgConf');
    my $content = $webCtl->postJson( $url, $params );
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

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

    #TODO: uncomment after test
    return;

    #TODO:Test end#################

    my $params = $self->_getParams($buildEnv);
    while ( my ( $key, $val ) = each(%$measures) ) {
        $params->{$key} = $val;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('addBuildQuality');
    my $content = $webCtl->postJson( $url, $params );
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

    #TODO: 测试 提交sonarqube扫描结果数据到后台，老版本有相应的实现
    return;
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

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getAppPassWord');
    my $content = $webCtl->postJson( $url, $params );
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

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
    my ( $self, $jobId, $deployEnv ) = @_;

    #TODO: delete follow test lines
    #格式：
    my $sqlInfoList = [];

    return $sqlInfoList;

    #TODO: test lines end#####################3

    #返回数据格式
    # [
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
    #]

    my $params = {};

    if ( defined($deployEnv) ) {

        #获取应用发布某个环境的所有的SQL状态List
        $params = $self->_getParams($deployEnv);
    }
    else {
        #获取某个作业的所有的SQL状态List
        $params->{jobId} = $jobId;
    }

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('getSqlFileStatuses');
    my $content = $webCtl->postJson( $url, $params );
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

    my $sqlInfoList = $rcObj;

    return $sqlInfoList;
}

sub checkInSqlFiles {
    my ( $self, $jobId, $sqlInfoList, $deployEnv ) = @_;

    #TODO: uncomment after test

    if ( defined($deployEnv) ) {
        my $params = $self->_getParams($deployEnv);
        foreach my $sqlInfo (@$sqlInfoList) {
            while ( my ( $k, $v ) = each(%$params) ) {
                $sqlInfo->{$k} = $v;
                $sqlInfo->{operType} = 'deploy';
            }
        }
    }

    print Dumper ($sqlInfoList);
    return;

    #TODO:Test end#################

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

    my $params = $self->_getParams($deployEnv);
    $params->{sqlInfoList} = $sqlInfoList;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('checkInSqlFiles');
    my $content = $webCtl->postJson( $url, $params );
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

    #TODO: 测试 保存sql文件信息到DB，工具sqlimport、dpsqlimport调用此接口

    return;
}

sub pushSqlStatus {
    my ( $self, $jobId, $sqlFileStatus, $deployEnv ) = @_;

    #TODO: Delete follow test lines
    print("DEBUG: update sql status to server.\n");
    print Dumper($sqlFileStatus);

    return;

    #TODO: Test ended#############################

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
    my $params = $self->_getParams($deployEnv);
    $params->{jobId}     = $jobId;
    $params->{sqlStatus} = $sqlFileStatus;

    my $webCtl  = $self->{webCtl};
    my $url     = $self->_getApiUrl('pushSqlStatus');
    my $content = $webCtl->postJson( $url, $params );
    my $rcJson  = from_json($content);

    my $rcObj;
    if ( $rcJson->{Status} eq 'OK' ) {
        $rcObj = $rcJson->{Return};
    }
    else {
        die( $rcJson->{Message} );
    }

    return;
}

sub addJob {
    my ( $self, $buildEnv, %args ) = @_;

    my $baseUrl   = $args{baseUrl};
    my $authToken = $args{authToken};
    if ( not defined($authToken) ) {
        $authToken = $self->_getAuthToken();
    }

    my $targetEnvPath = $args{targetEnvPath};
    my $targetVersion => $args{targetVersion};
    my $senario  = $args{senario};
    my $isRunNow = $args{isRunNow};
    my $isAuto   = $args{isAuto};
    my $waitJob  = $args{waitJob};
    my $planTime   => $args{planTime};
    my $roundCount => $args{roundCount};
    my $jobUser    => $args{jobUser};
    my $instances  => $args{instances};
    my $jobArgs = $args{jobArgs};

    #TODO: addJob
}

sub getJobStatus {
    my ( $self, $jobId, %args ) = @_;
    my $baseUrl   = $args{baseUrl};
    my $authToken = $args{authToken};
    if ( not defined($authToken) ) {
        $authToken = $self->_getAuthToken();
    }

    #TODO: getJobStatus
}

sub saveVersionDependency {
    my ( $self, $buildEnv, $data ) = @_;

    #TODO： save jar dependency infomations
}

sub getBuild {
    my ( $self, $deployEnv, $srcEnvInfo, $subDirs, $cleanSubDirs ) = @_;

    #download某个版本某个buildNo的版本制品到当前节点

    my $checked = 0;
    my $builded = 0;

    my $namePath  = $deployEnv->{_DEPLOY_PATH};
    my $version   = $deployEnv->{version};
    my $buildNo   = $deployEnv->{buildNo};
    my $buildPath = $deployEnv->{BUILD_PATH};

    if ( not -e $buildPath ) {
        mkpath($buildPath);
    }

    my $fh;
    sysopen( $fh, "$buildPath.lock", O_RDWR | O_CREAT | O_SYNC );
    if ( not defined($fh) ) {
        die("Can not open or create file $buildPath.lock, $!\n");
    }

    my $gzMagicNum  = "\x1f\x8b";
    my $tarMagicNum = "\x75\x73";
    my ( $pid, $reader, $writer, $releaseStatus, $contentDisposition, $magicNum, $firstChunk );
    my $callback = sub {
        my ( $chunk, $res ) = @_;
        if ( $checked == 0 ) {
            $checked = 1;
            if ( $res->code eq 200 ) {
                $releaseStatus      = $res->header('Build-Status');
                $contentDisposition = $res->header('Content-Disposition');
                if ( $releaseStatus eq 'released' ) {
                    print("INFO: Build-Status:$releaseStatus\n");
                    print("INFO: Try to lock directory $buildPath");
                    flock( $fh, LOCK_EX );
                    print("INFO: Locked.\n");
                    $builded = 1;
                    if ( $cleanSubDirs == 1 ) {
                        foreach my $subDir (@$subDirs) {
                            foreach my $dir ( glob("$buildPath/$subDir") ) {
                                if ( -e $dir ) {

                                    #print("INFO: clean dir:$dir\n");
                                    rmtree($dir) or die("remove $dir failed.\n");
                                }
                            }
                        }
                    }
                    else {
                        if ( -e $buildPath ) {
                            rmtree($buildPath) or die("remove $buildPath failed.\n");
                            mkdir($buildPath);
                        }
                    }

                    $magicNum = substr( $chunk, 0, 2 );
                    my $cmd = "| tar -C '$buildPath' -xf -";
                    if ( $contentDisposition =~ /\.gz"?$/ or $magicNum eq $gzMagicNum ) {
                        $cmd = "| tar -C '$buildPath' -xzf -";
                    }
                    $pid = open( $writer, $cmd ) or die("open tar cmd failed:$!");
                    binmode($writer);
                }
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
    my $url    = $self->_getApiUrl('getBuild');

    my $pdata = $self->_getParams($deployEnv);

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

    if ( defined($subDirs) and scalar($subDirs) > 0 ) {
        $pdata->{'subDirs'} = join( ',', @$subDirs );
    }

    my $params = $client->buildQuery($pdata);
    $url = $url . $params;

    #$url = $url . "?agentId=$agentId&action=getappbuild&sysId=$sysId&subSysId=$subSysId&version=$version";

    $client->getUseragent()->ssl_opts( verify_hostname => 0 );
    $client->getUseragent()->ssl_opts( SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE );
    $client->getUseragent()->timeout(1200);
    $client->addHeader( 'Authorization', $self->_getAuthToken() );
    $client->setFollow(1);
    $client->setContentFile( \&$callback );

    $client->GET($url);
    $releaseStatus = $client->responseHeader('Build-Status');

    my $untarCode = -1;
    if ( defined($writer) ) {
        close($writer);

        #waitpid( $pid, 0 );
        $untarCode = $?;

        #print("DEBUG: untar return code:$untarCode\n");
    }

    flock( $fh, LOCK_UN );

    if ( $client->responseCode() ne 200 ) {
        my $errMsg = $client->responseContent();
        die("Get build namePath Version:$version build$buildNo failed with status:$releaseStatus, cause by:$errMsg\n");
    }

    if ( $releaseStatus ne 'released' ) {

        my $errMsg = $client->responseContent();
        if ( defined($releaseStatus) and $releaseStatus ne '' ) {
            if ( $releaseStatus eq 'null' ) {
                die("$namePath Version:$version build$buildNo not exists.\n");
            }
            else {
                die("Version $version build$buildNo in error status:$releaseStatus.\n");
            }
        }
        else {
            die("Get resources failed: $errMsg\n");
        }
    }

    if ( $untarCode ne 0 ) {
        die("Get resources failed with status:$releaseStatus, build resource is empty or data corrupted because of network timeout problem.\n");
    }

    #TODO: 通过getres测试检查
    return $releaseStatus;
}

1;
