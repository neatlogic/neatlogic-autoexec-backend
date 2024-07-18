#!/bin/bash
PROG_PATH=${BASH_SOURCE[0]}
echo $PROG_PATH
AUTOEXEC_DIR=$(cd $(dirname "$PROG_PATH")/.. && pwd)

echo "NOTICE：Please source this script:. $AUTOEXEC_DIR/devenv.sh"

export PYTHONPATH=.:$AUTOEXEC_DIR/plugins/local/lib:$AUTOEXEC_DIR/lib:$AUTOEXEC_DIR/plib
export PERL5LIB=.:$AUTOEXEC_DIR/plugins/local/lib:$AUTOEXEC_DIR/plugins/local/pllib/lib/perl5
export PATH=.:$AUTOEXEC_DIR/plugins/local/bin:$AUTOEXEC_DIR/plugins/local/tools:$AUTOEXEC_DIR/plugins/local/bin:$PATH

echo PYTHONPATH=$PYTHONPATH
echo PERL5LIB=$PERL5LIB
echo PATH=$PATH

export DEV_MODE=1
export RUNNER_ID=1
export _DEPLOY_RUNNERGROUP="",
export AUTOEXEC_TENANT=develop
export AUTOEXEC_JOBID=0
export AUTOEXEC_PHASE_NAME=collect
export AUTOEXEC_WORK_PATH=/tmp
export OUTPUT_PATH=/tmp/output.json
export LIVEDATA_PATH=/tmp/livedata.json

export AUTOEXEC_NODE='{"nodeName":"switch","protocol":"snmp","password":"Tpublic","resourceId":0,"host":"192.168.0.1","nodeType":"Switch","nodeId":0,"protocolPort":161,"username":"root"}'

export _IS_RELEASE=1
export _DEPLOY_PATH=k8sTest/springbootdemo/PRD
export _DEPLOY_ID_PATH=847563837988864/847564165144576/481856650534914
export _VERSION=1.0.0
export _BUILD_NO=1
