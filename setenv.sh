#!/usr/bin/bash
SCRIPT_DIR=$(dirname "$SOURCE_PATH")
if [ "$SCRIPT_DIR"="." ]
then
    SCRIPT_DIR=$(pwd)
fi

echo "NOTICE：Please source this script:. ./setenv.sh"

export PYTHONPATH=.:$SCRIPT_DIR/plugins/local/lib:$SCRIPT_DIR/lib:$SCRIPT_DIR/plib
export PERL5LIB=.:$SCRIPT_DIR/plugins/local/lib/perl-lib/lib/perl5
export PATH=.:$SCRIPT_DIR/plugins/local/bin:$SCRIPT_DIR/plugins/local/tools:$SCRIPT_DIR/plugins/local/bin:$PATH

echo PYTHONPATH=$PYTHONPATH
echo PERL5LIB=$PERL5LIB
echo PATH=$PATH

