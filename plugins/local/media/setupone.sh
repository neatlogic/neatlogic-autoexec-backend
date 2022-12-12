#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PRE_CWD=$(pwd)
cd $(dirname $0)
PERL_MEDIA_HOME=$(pwd)
PL_LIB_PATH=$(cd "$PERL_MEDIA_HOME/../pllib" && pwd)
AUTOEXEC_HOME=$(cd "$PERL_MEDIA_HOME/../../.." && pwd)

if [ "$PL_LIB_PATH" == "" ]; then
        echo "Can not determin the perl lib path, exit."
        exit 1
fi

echo "MEDIA HOME:$PERL_MEDIA_HOME"
echo "AUTOEXEC HOME:$AUTOEXEC_HOME"

export PERL5LIB=.:$PL_LIB_PATH/lib/perl5:$PERL5LIB
export PERL_MM_USE_DEFAULT=1                    #安装交互中使用default值自动应答
export PERL_EXTUTILS_AUTOINSTALL=--default-deps #安装交互中依赖自动安装默认依赖

install_base=$PL_LIB_PATH

cd $PERL_MEDIA_HOME/perl-pkgs || exit 1

echo "Delete directory in media path"
for dir in $*; do
        if [ "$dir" != "." -a "$dir" != ".." -a -d "$dir" ]; then
                echo -e "${BLUE}Delete directory $dir${NC}"
                rm -rf $dir
                if [[ $? != 0 ]]; then
                        echo -e "${RED}ERROR: Remove $dir failed.${NC}"
                fi
        fi
done

echo "Extrace perl packages in $PERL_MEDIA_HOME..."
for file in $*; do
        if [ ! -e "$file" ]; then
                tarFile="$file.tar.gz"
        else
                tarFile=$file
        fi

        echo -e "${BLUE}Extract file '$tarFile'${NC}"
        tar -xzf "$tarFile"
        if [[ $? != 0 ]]; then
                echo -e "${RED}ERROR: Extract $tarFile failed.${NC}"
        else
                if [ ! -e "$file" ]; then
                        unTarFile=${file%-[.0-9]*}
                        if [ -e "$unTarFile" ]; then
                                mv $unTarFile $file
                        fi
                fi
        fi
done

declare -a INS_SUC_PKGS
declare -a INS_FAIL_PKGS
declare -i INSTALL_COUNT=0
echo "Begin install perl pkgs......"
pwd

for dir in $*; do
        dir=${dir%.tgz}
        dir=${dir%.tar.gz}
        dir=${dir#*/}
        if [[ $dir == DBD-Oracle* ]]; then
                #oracle DBD
                echo -e "${BLUE}Try to install package:${dir}${NC}"
                cd $dir
                export ORACLE_HOME=$AUTOEXEC_HOME/tools/oracle-client
                export LD_LIBRARY_PATH=$ORACLE_HOME/lib
                perl Makefile.PL INSTALL_BASE=$install_base -V 12.1.0 -h $ORACLE_HOME/sdk/include && make && make install
                if [[ $? -ne 0 ]]; then
                        echo -e "${RED}ERROR: Install package:$dir failed.${NC}"
                        INS_FAIL_PKGS+=($dir)
                else
                        echo -e "${GREEN}Package:$dir install success.${NC}"
                        INS_SUC_PKGS+=($dir)
                fi
                cd $PERL_MEDIA_HOME/perl-pkgs
                INSTALL_COUNT=INSTALL_COUNT+1
        elif [[ -e "$dir/Build.PL" ]]; then
                echo -e "${BLUE}Try to install package:${dir}${NC}"
                cd $dir
                perl Build.PL --install_base $install_base && ./Build install
                if [[ $? -ne 0 ]]; then
                        echo -e "${RED}ERROR: Install package:$dir failed.${NC}"
                        INS_FAIL_PKGS+=($dir)
                else
                        echo -e "${GREEN}Package:$dir install success.${NC}"
                        INS_SUC_PKGS+=($dir)
                fi
                cd $PERL_MEDIA_HOME/perl-pkgs
                INSTALL_COUNT=INSTALL_COUNT+1
        elif [[ -e "$dir/Makefile.PL" ]]; then
                echo -e "${BLUE}Try to install package:${dir}${NC}"
                cd $dir
                perl Makefile.PL INSTALL_BASE=$install_base && make && make install
                if [[ $? -ne 0 ]]; then
                        echo -e "${RED}ERROR: Install package:$dir failed.${NC}"
                        INS_FAIL_PKGS+=($dir)
                else
                        echo -e "${GREEN}Package:$dir install success.${NC}"
                        INS_SUC_PKGS+=($dir)
                fi
                cd $PERL_MEDIA_HOME/perl-pkgs
                INSTALL_COUNT=INSTALL_COUNT+1
        fi
done

if [[ $INSTALL_COUNT == 0 ]]; then
        echo -e "${RED}ERROR: Can not find any pakcages untar directory.${NC}"
        echo -e "${RED}Please execute clean.sh before.${NC}"
fi

for PKG in ${INS_SUC_PKGS[@]}; do
        echo -e "${GREEN}${PKG} install success.${NC}"
done

for PKG in ${INS_FAIL_PKGS[@]}; do
        echo -e "${RED}${PKG} install failed.${NC}"
done

cd $PRE_CWD
