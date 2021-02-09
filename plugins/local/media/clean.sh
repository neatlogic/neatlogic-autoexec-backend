#!/bin/bash
PRE_CWD=`pwd`
cd `dirname $0`
PERL_MEDIA_HOME=`pwd`

install_base=$TECHSURE_HOME/autoexec/plugins/local/lib/perl-lib

if [ ! "$#" = "1" ]
then
	if [ -z "$TECHSURE_HOME" ]
	then
		echo "\$TECHSURE_HOME not defined, rerun it after export TECHSURE_HOME=/xxxx";
		exit -1;
	fi
else
	install_base=$1
fi

cd $PERL_MEDIA_HOME/perl-pkgs || exit 1;

echo "Delete share lib(so file) in $install_base"
#find . -name '*.so' -not -name 'Oracle.so' -not -name 'mysql.so'
find $install_base -name '*.so' -not -name 'mysql.so' -exec rm -f {} \;

echo "Delete directory in media path"
for dir in `find . -maxdepth 1 -type d`
do
  if [ "$dir" != "." -a "$dir" != ".." ]
  then
    rm -rf $dir
  fi
done

echo "extrace perl packages in media path"
for file in `find . -maxdepth 1 -type f`
do
       echo "untar $file"
        tar -xmzvf $file
done

