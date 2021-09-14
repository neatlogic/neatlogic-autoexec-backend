#!/bin/sh

# $Header: mkconf.sh 1.00 14/12/2000 RM Copyright (c) 2000-2017, Hitachi, Ltd.
# 
# NAME  : MaKe a Configuration File
#
# DESCRIPTION:
# Format : mkconf.sh { -g[g] <group> [-m <mu#>] [-i <inst#>] [-s <service>] [-a] }
#      -g[g] <group> Specify the dev_group for a configuration file.
#                    If not specified, 'VG' will be used as default.
#     [-m <mu#>  ]   Specify the mirror descriptor for BC(MRCF) volume.
#                    Specify the mirror descriptor as '-m h1' for UR volume.
#                    CA(HORC) volume dose not specify the mirror descriptor.
#     [-i <inst#>]   Specify the instance number for HORCM.
#     [-s <service>] Specify the service name for a configuration file.
#                    If not specified, '52323' will be used as default.
#     [-a]           Specify an addition of the group for a configuration file.
#
#
#  
# CHANGELOG 
# Revision 1.14   28/05/2014   Changed FINDCMD from '/sbin/ioscan -fun' to 'echo /dev/*/*' for HPVM.
#                              Added 'echo ioscan -Nfun' for NPIV HBA mapping on HPVM.
# Revision 1.13   09/01/2013   Changed FINDCMD from '/bin/ls /dev/rdsk/*s2' to 'echo /dev/rdsk/*'.
# Revision 1.12   22/03/2012   Added "/dev/rcdisk/" for the Cluster DSF 
# Revision 1.11   28/06/2010   Added "raidcfg -logtst" for User authentication
# Revision 1.10   24/04/2006   Added "/dev/rdisk/*" for HP-UX11.31.
# Revision 1.09   14/03/2006   Changed to '/bin/grep' from 'grep'.
# Revision 1.08   18/11/2004   Supported '-m h#' as cascading MU# for UR.
#                              Supported '/dev/cport/scp*' as CMDDEV for Tru64.
# Revision 1.07   18/04/2003   Supported the -gg option for displaying a host group.
# Revision 1.06   20/03/2002   Added 'sleep 5' for waitting the horcmshutdown. 
# Revision 1.05   20/02/2002   Changed the directory from '/etc/lsdev' to
#                              '/usr/sbin/lsdev'. 
# Revision 1.04   26/10/2001   Bug fix for 'if [ "FINDCMD2" = "" ]'
# Revision 1.03   01/08/2001   Added '2>/dev/null' to arg of RTYCMD.
# Revision 1.02   23/04/2001   Added IRIX64 to the plat.
# Revision 1.01   06/04/2001   Changed the localhost to '127.0.0.1'. 
# Revision 1.00   14/12/2000   k.urabe Initial revision




# [STARTING POINT]:

umask 0
curdir=`pwd`
osname=`uname`
makeday=`date`

SCANDEV="/tmp/scandevtmp"
# OUTCONF="${curdir}/horcm*.conf"
# OWNHOST=`hostname`
if [ "$osname" != "MPE/iX" ]
  then
    OWNHOST="127.0.0.1"
  else
    OWNHOST="NONE"
fi
RMTHOST="127.0.0.1"


# Cmdrty() is used for execute horcmstart.sh with background such as MPE/iX,
# and need to re-try a command with error(251 or 250).

cmdrty(){
  count=$1
  go=1
  while [ $go -ne 0 ]
  do
    eval $RTYCMD 
    status=$?
    if [ $status -ne 0 -a $status -ne 251 -a $status -ne 250 ]
      then 
        echo "$CMDERRMSG" 
        go=0
      elif [ $status -eq 0 ]
      then
        go=0
      elif [ $count -eq 0 ]
      then
        echo "Timeout: Can't attached to HORC manager."
        go=0
      else
       count=`expr $count - 1`
       sleep 3
    fi
  done
  return $status ;
}

# RTYCMD="./exit.sh $1"
# CMDERRMSG="Could not find the target devices."
# cmdrty 3 
# exit 0

argc=0
aparm=0
gparm=0
ggparm=0
GROUP=""
iparm=0
INST=""
mparm=0
MUN=""
sparm=0
SERVICE=""

for arg in $*
do
  argc=`expr $argc + 1`
  if [ "$arg" = "-g" ]
    then
      gparm=`expr $argc + 1`
    elif [ "$arg" = "-gg" ]
    then
      ggparm=`expr $argc + 1`
    elif [ "$arg" = "-i" ]
    then
      iparm=`expr $argc + 1`
    elif [ "$arg" = "-m" ]
    then
      mparm=`expr $argc + 1`
    elif [ "$arg" = "-s" ]
    then
      sparm=`expr $argc + 1`
    elif [ "$arg" = "-a" ]
    then
      aparm=`expr $argc + 1`
    else
      if [ $gparm -eq $argc -o $ggparm -eq $argc ]
        then
          GROUP="$arg"
        elif [ $iparm -eq $argc ]
        then
          INST="$arg"
        elif [ $mparm -eq $argc ]
        then
          MUN="$arg"
        elif [ $sparm -eq $argc ]
        then
         SERVICE="$arg"
      fi
  fi
done

help=0
if [ "$GROUP" = "" -a "$INST" = "" -a "$MUN" = ""  ]
  then
    echo "Usage : $0"
    echo "    -g[g] <group> Specify the dev_group for a configuration file."
    echo "                  If not specified, 'VG' will be used as default."
    echo "   [-m <mu#>  ]   Specify the mirror descriptor for BC(MRCF) volume."
    echo "                  Specify the mirror descriptor as '-m h1' for UR volume."
    echo "                  CA(HORC) volume dose not specify the mirror descriptor."
    echo "   [-i <inst#>]   Specify the instance number for HORCM."
    echo "                  No running HORCM instance must be specified."
    echo "   [-s <service>] Specify the service name for a configuration file."
    echo "                  If not specified, '52323' will be used as default."
    echo "   [-a]           Specify an addition of the group for a configuration file."
    echo "Example:"
    help=1
fi

FINDCMD2=""
case $osname in
  HP-UX)
        if [ $help -eq 1 ]
          then
            echo "vgdisplay -v /dev/vg01 | grep dsk | sed 's/\/*\/dsk\//\/rdsk\//g'| $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "cat dev_file           | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rdsk/*         | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rdisk/*        | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rcdisk/*       | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ioscan -fun  |grep -e rdisk -e rdsk -e rcdisk | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ioscan -Nfun |grep -e rdisk -e rdsk -e rcdisk | $0 -g dev_group -i 9 [-m 0] [-a]"
        fi
#      FINDCMD="/sbin/ioscan -fun | /bin/grep -e rdisk -e rdsk | /HORCM/usr/bin/inqraid -sort -CM -CLI"
        FINDCMD="echo /dev/rdsk/* /dev/rdisk/* /dev/rcdisk/* | /HORCM/usr/bin/inqraid -sort -CM -CLI"
        ;;
  SunOS)
        if [ $help -eq 1 ]
          then
            echo "vxdisk list      | grep dev_group | $0 -g vg_name -i 9 [-m 0] [-a]"
            echo "cat dev_file     | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rdsk/*s2 | $0 -g dev_group -i 9 [-m 0] [-a]"
        fi
        FINDCMD="echo /dev/rdsk/*s2 | /HORCM/usr/bin/inqraid -sort -CM -CLI"
        ;;
    AIX)
        if [ $help -eq 1 ]
          then
            echo "lsvg -p vg_name | grep hdisk | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "cat dev_file    | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rhdisk* | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "lsdev -C -c disk| grep hdisk | $0 -g dev_group -i 9 [-m 0] [-a]"
        fi
        FINDCMD="/usr/sbin/lsdev -C -c disk | /bin/grep hdisk | /HORCM/usr/bin/inqraid -sort -CM -CLI"
       ;;
    OSF1)
        if [ $help -eq 1 ]
          then
            echo "cat dev_file        | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rrz*c       | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rdisk/dsk*c | $0 -g dev_group -i 9 [-m 0] [-a]"
        fi
        FINDCMD="echo /dev/rdisk/dsk*c /dev/cport/scp* 2>/dev/null | /HORCM/usr/bin/inqraid -sort -CM -CLI"
        FINDCMD2="echo /dev/rrz*c 2>/dev/null | /HORCM/usr/bin/inqraid -sort -CM -CLI"
        ;;
  Linux)
        if [ $help -eq 1 ]
          then
            echo "cat dev_file | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/sd*  | $0 -g dev_group -i 9 [-m 0] [-a]"
        fi
        FINDCMD="echo /dev/sd* | /HORCM/usr/bin/inqraid -sort -CM -CLI"
        ;;
  MPE/iX)
        if [ $help -eq 1 ]
          then
            echo "cat dev_file | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/ldev*| $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "callci dstat | $0 -g dev_group -i 9 [-m 0] [-a]"
        fi
        FINDCMD="callci dstat | /HORCM/usr/bin/inqraid -sort -CM -CLI -inst"
        ;;
  DYNIX/ptx)
        if [ $help -eq 1 ]
          then
            echo "cat dev_file     | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rdsk/sd* | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "dumpconf -d | grep sd | $0 -g dev_group -i 9 [-m 0] [-a]"
        fi
        FINDCMD="/etc/dumpconf -d | /bin/grep sd | /HORCM/usr/bin/inqraid -sort -CM -CLI"
        ;;
    IRIX64)
        if [ $help -eq 1 ]
          then
            echo "cat dev_file          | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rdsk/*vol     | $0 -g dev_group -i 9 [-m 0] [-a]"
            echo "ls /dev/rdsk/*/*vol/* | $0 -g dev_group -i 9 [-m 0] [-a]"
        fi
        FINDCMD="echo /dev/rdsk/*vol /dev/rdsk/*/*vol/* 2>/dev/null | /HORCM/usr/bin/inqraid -sort -CM -CLI"
        ;;
      *)
        echo "Raid Manager does not support OS(${osname}) on this machine."
        exit 1 ;;
esac

if [ $help -eq 1 ]
  then
    exit 1
fi


if [ "$INST" = "" ]
  then
    unset HORCMINST 
    OUTCONF="${curdir}/horcm.conf"
    HORCM_LOG="${curdir}/log/curlog"
    HORCM_LOGS="${curdir}/log/tmplog"
  else
    HORCMINST="$INST" 
    export HORCMINST 
    OUTCONF="${curdir}/horcm${INST}.conf"
    HORCM_LOG="${curdir}/log${INST}/curlog"
    HORCM_LOGS="${curdir}/log${INST}/tmplog"
fi

case $MUN in
  h*)
     unset HORCC_MRCF
     ;;
  "")
     MUN=0
     unset HORCC_MRCF
     ;;
  *)
     HORCC_MRCF=1
     export HORCC_MRCF
     ;;
esac

if [ "$GROUP" = "" ]
  then
    GROUP="VG"
fi

if [ "$SERVICE" = "" ]
  then
    SERVICE="52323" 
fi

HORCM_CONF=$OUTCONF
export HORCM_CONF
export HORCM_LOG
export HORCM_LOGS

HORCC_LOG="STDERROUT"
export HORCC_LOG

HORCMPERM="MGRNOINST"
export HORCMPERM

# echo "$GROUP"
# echo "$INST"
# echo "$MUN"
# echo "$OUTCONF"
# echo "$SERVICE"
# exit 0

# [Start 'inqraid -sort -CM -CLI' in order to discover the Command devices.]

if [ $aparm -eq 0 ]
  then
    echo "# Created by mkconf.sh on $makeday" > $OUTCONF
    printf "\nHORCM_MON\n" >> $OUTCONF
    printf "#ip_address        service         poll(10ms)     timeout(10ms)\n" >> $OUTCONF
    printf "%-18s %-15s %10d     %13d\n\n" "$OWNHOST" "$SERVICE" 1000 3000  >> $OUTCONF

    eval $FINDCMD 1>> $OUTCONF 
    if [ $? -ne 0 ]
      then
        if [ "$FINDCMD2" = "" ]
          then 
            echo "Could not find a command device."
            /bin/rm -rf $OUTCONF 
            exit 1
          else
            eval $FINDCMD2 1>> $OUTCONF 
            if [ $? -ne 0 ]
              then 
                echo "Could not find a command device."
                /bin/rm -rf $OUTCONF 
                exit 1
            fi
        fi
    fi
    printf "\n" >> $OUTCONF
  else
    if [ ! -f $OUTCONF ]
      then
        echo "Could not find a '${OUTCONF}' file."
        exit 1
    fi
fi

# MPE/iX will unable to detect an error(already running error)
# due to background so that this command will be completed. 
if [ "$osname" = "MPE/iX" ]
  then
    /HORCM/usr/bin/raidqry -l > /dev/null 2>/dev/null
    if [ $? -eq 0 ]
      then 
        if [ "$INST" = "" ]
          then
            echo "HORCM has already been running."
          else
            echo "HORCM inst $INST has already been running."
        fi
        echo "Could not start an HORCM."
        exit 1
    fi
fi

# [Starting HORCM for execution of raidscan -find. ]

if [ "$osname" != "MPE/iX" ]
  then
    /HORCM/usr/bin/horcmstart.sh 
  else
    /HORCM/usr/bin/horcmstart.sh &
    sleep 5
fi
if [ $? -ne 0 ]
  then 
    echo "Could not start an HORCM."
    exit 1
fi

# Verify User authentication  
/HORCM/usr/bin/raidcfg -logtst
if [ $? -ne 0 ]
  then
    /HORCM/usr/bin/horcmshutdown.sh 
    exit 1    
fi


# Wait for all STDIN data
cat > $SCANDEV

if [ $ggparm -ne 0 ]
  then
    RTYCMD="/bin/cat $SCANDEV | /HORCM/usr/bin/raidscan -findg conf $MUN -g $GROUP 1>> $OUTCONF 2>/dev/null"
  else
    RTYCMD="/bin/cat $SCANDEV | /HORCM/usr/bin/raidscan -find conf $MUN -g $GROUP 1>> $OUTCONF 2>/dev/null"
fi

CMDERRMSG="Could not find the target devices."
cmdrty 20
status=$?
/HORCM/usr/bin/horcmshutdown.sh 

if [ $status -ne 0 ]
  then
    exit 1    
fi

printf "\nHORCM_INST\n" >> $OUTCONF
printf "#dev_group        ip_address      service    \n" >> $OUTCONF
printf "%-17s %-15s %-10s\n\n" "$GROUP" "$RMTHOST" "$SERVICE" >> $OUTCONF

echo "A CONFIG file was successfully completed."


# [Starting HORCM for verification of a CONFIG file. ]
# Verify for SCANDEV and HORCMPERM need to use -fd option.

sleep 5

HORCMPERM=$SCANDEV
export HORCMPERM

if [ "$osname" != "MPE/iX" ]
  then
    /HORCM/usr/bin/horcmstart.sh 
  else
    /HORCM/usr/bin/horcmstart.sh &
fi
if [ $? -ne 0 ]
  then 
    echo "Could not start an HORCM on the verify state."
    exit 1
fi

RTYCMD="/bin/cat $SCANDEV | /HORCM/usr/bin/raidscan -find verify $MUN 2>/dev/null"
CMDERRMSG="Could not executes 'raidscan -find verify' command."
cmdrty 20
status=$?
/HORCM/usr/bin/horcmshutdown.sh

if [ $status -ne 0 ]
  then
    exit 1    
fi
 
echo "Please check '${OUTCONF}','${HORCM_LOG}/horcm_*.log', and modify 'ip_address & service'."

exit 0



    
