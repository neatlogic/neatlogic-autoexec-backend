#!/usr/bin/bash
PROG_PATH=${BASH_SOURCE[0]}
echo $PROG_PATH
SCRIPT_DIR=$(cd $(dirname "$PROG_PATH") && pwd)

echo "NOTICE：Please source this script:. $SCRIPT_DIR/setenv.sh"

export PYTHONPATH=.:$SCRIPT_DIR/plugins/local/lib:$SCRIPT_DIR/lib:$SCRIPT_DIR/plib
export PERL5LIB=.:$SCRIPT_DIR/plugins/local/lib:$SCRIPT_DIR/plugins/local/pllib/lib/perl5
export PATH=.:$SCRIPT_DIR/plugins/local/bin:$SCRIPT_DIR/plugins/local/tools:$SCRIPT_DIR/plugins/local/bin:$PATH

echo PYTHONPATH=$PYTHONPATH
echo PERL5LIB=$PERL5LIB
echo PATH=$PATH
