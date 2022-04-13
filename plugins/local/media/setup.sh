#!/bin/bash
PRE_CWD=$(pwd)
cd $(dirname $0)
PERL_MEDIA_HOME=$(pwd)
PL_LIB_PATH=$(cd "$PERL_MEDIA_HOME/../pllib" && pwd)

if [ "$PL_LIB_PATH" == "" ]; then
        echo "Can not determin the perl lib path, exit."
        exit 1
fi

echo "MEDIA HOME:$PERL_MEDIA_HOME"

export PERL5LIB=.:$PL_LIB_PATH/lib/perl5:$PERL5LIB

install_base=$PL_LIB_PATH

cd $PERL_MEDIA_HOME/perl-pkgs || exit 1

#echo "Delete share lib(so file) in $install_base"
#find $install_base -name '*.so' -exec rm -f {} \;

#echo "Delete directory in media path"
#for dir in `find . -maxdepth 1 -type d`
#do
#  if [ "$dir" != "." -a "$dir" != ".." ]
#  then
#    rm -rf $dir
#  fi
#done

#echo "extrace perl packages in media path"
#for file in `find . -maxdepth 1 -type f`
#do
#	echo "untar $file"
#        tar -xmzvf $file
#done

echo "Begin install perl pkgs......"
pwd

for dir in $(find . -maxdepth 1 -type d); do
        if [ -e "$dir/Build.PL" ]; then
                cd $dir
                perl Build.PL --install_base $install_base
                #perl Build.PL --prefix $install_base
                ./Build install
                cd ..
        fi

        if [ -e "$dir/Makefile.PL" ]; then
                cd $dir
                perl Makefile.PL INSTALL_BASE=$install_base
                #perl Makefile.PL PREFIX=$install_base
                make
                make install
                cd ..
        fi
done

#oracle DBD
for dir in DBD-Oracle*; do
        if [ -d $dir ]; then
                cd $dir
                export ORACLE_HOME=$TECHSURE_HOME/ezdeploy/tools/oracle-client
                export LD_LIBRARY_PATH=$ORACLE_HOME/lib
                perl Makefile.PL INSTALL_BASE=$TECHSURE_HOME/ezdeploy/lib/perl-lib -V 12.1.0 -h $ORACLE_HOME/sdk/include
                make
                make install
                cd ..
        fi
done

#copy the WinRM.pm Expect.pm to perl-lib
unalias cp >/dev/null 2>&1
echo "cp -rf $PERL_MEDIA_HOME/perl-lib/* $install_base/"
cp -rf $PERL_MEDIA_HOME/perl-lib/* $install_base/

cd $PRE_CWD
