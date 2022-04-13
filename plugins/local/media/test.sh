#!/bin/bash
cd $(dirname $0)
PERL_MEDIA_HOME=$(pwd)
PL_LIB_PATH=$(cd "$PERL_MEDIA_HOME/../pllib" && pwd)

if [ "$PL_LIB_PATH" == "" ]; then
    echo "Can not determin the perl lib path, exit."
    exit 1
fi

install_base=$PL_LIB_PATH

echo $PERL_MEDIA_HOME
echo $PL_LIB_PATH
