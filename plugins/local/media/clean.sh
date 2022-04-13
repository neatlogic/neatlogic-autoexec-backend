#!/bin/bash
PRE_CWD=$(pwd)
cd $(dirname $0)
PERL_MEDIA_HOME=$(pwd)
PL_LIB_PATH=$(cd "$PERL_MEDIA_HOME/../pllib" && pwd)

if [ "$PL_LIB_PATH" == "" ]; then
  echo "Can not determin the perl lib path, exit."
  exit 1
fi

install_base=$PL_LIB_PATH

cd $PERL_MEDIA_HOME/perl-pkgs || exit 1

echo "Delete directory in media path"
for dir in $(find . -maxdepth 1 -type d); do
  if [ "$dir" != "." -a "$dir" != ".." ]; then
    rm -rf $dir
  fi
done

cd $PRE_CWD
