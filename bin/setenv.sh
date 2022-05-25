#!/usr/bin/bash
PROG_PATH=${BASH_SOURCE[0]}
echo $PROG_PATH
AUTOEXEC_DIR=$(cd $(dirname "$PROG_PATH")/.. && pwd)

echo "NOTICE：Please source this script:. $AUTOEXEC_DIR/setenv.sh"

export PYTHONPATH=.:$AUTOEXEC_DIR/plugins/local/lib:$AUTOEXEC_DIR/lib:$AUTOEXEC_DIR/plib
export PERL5LIB=.:$AUTOEXEC_DIR/plugins/local/lib:$AUTOEXEC_DIR/plugins/local/pllib/lib/perl5
export PATH=.:$AUTOEXEC_DIR/plugins/local/bin:$AUTOEXEC_DIR/plugins/local/tools:$AUTOEXEC_DIR/plugins/local/bin:$PATH

echo PYTHONPATH=$PYTHONPATH
echo PERL5LIB=$PERL5LIB
echo PATH=$PATH
