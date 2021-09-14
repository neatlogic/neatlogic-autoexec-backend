#!/bin/bash

##-------------------------------------------------------------------#
## %PS
##    
## Licensed Internal Code - Property of IBM
##    
## 2105/2107/1750 Licensed Internal Code
##    
## (C) Copyright IBM Corp. 1999, 2006 All Rights Reserved.
##    
## US Government Users Restricted Rights - Use, duplication or
## disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
## %EPS
##
## COMPONENT_NAME (RAS WUI)
##
##-------------------------------------------------------------------#
##
## Filename: lshostvol.sh
##
## Subsystem: RAS WUI
##
## Input:   lshostvol.sh
##
## Description: The lshostvol command displays the mapping of host
##              device or volume names to 2107, 2105 and 1750 volume
##              IDs
##
###
### Legacy Change History:
##-------------------------------------------------------------------#
###  Richard Kirchhofer     11-19-1999            28254
###      Initial version
###  Ruth Azevedo           05-31-2000
###      Put warning for HP for ESS serial number
###  Ramandeep Kaur         06-12-2000                    36001,
###      Fixed Missing serial number for Sun              36002
###      Fixed allignment of output for Sun
###  Ramandeep Kaur         06-28-2000                    34802
###      Included functionality to get ESS serial numbers
###      Deleted warning for HP for ESS serial number
###  John Wrobel            08-03-2000                    38511
###      Modifies return codes
###  Ramandeep Kaur         08-08-2000                    39105
###      Modifies return codes
###  Susanne Lukas &        11-14-2000                    43080
###  Ramandeep Kaur
###      Included check on datapath output file.
###  Ramandeep Kaur         02-26-2001                    47568
###      Included code to support Numaq
###  Susanne Lukas          03-08-2001                    48395
###      Creating a file containing the serial numbers and volume names
###  Ramandeep Kaur         05-29-2001                    51827
###      Modified the prologline and comments line to start
###      with ###
###  Susanne Lukas          05-16-2002                    53514
###      Implemented code to support Linux
###  Amy Therrien           09-14-2001                    58685
###      Remove additional newline in Dynix/ptx query of volumes
###  Susanne Lukas          06-15-2001                    56209
###      Implemented code to support Tru64
###  Monica Chu             11-15-2001                    60708
###      Correct display of tab under Linux
###  Susanne Lukas          02-05-2002                    64770
###     Setup a special tag for the TRU64 installation variable
###  John Wrobel        02-18-2002            63465
### Made script compatible with HPUX11i
###  Monica Chu             03-01-2002                    66109
###     Moved the comment for 60708 one line above the OS checking
###     so the line won't be deleted 
###  Amy Therrien           04-05-2002                    68207
###     Check to see if volumes are actually configured for SUN
###  John Wrobel       06/07/02           71500
###  Added support for Linux.
###  Matthew Ward            06-27-02                     71621
###     Fixed unmatched " and changed /dev/nulli to /dev/null
###  Amy Therrien           22-Sep-2002                   76078
###     Add support for wbCsLinuxDPO.exe,remove 71500
###  Amy Therrien           07-Oct-2002                   76636
###     Add DPO for Linux
###  Matthew Ward           13-November-2002              75956
###     Changed the export INSTALL statement to allow users
###     to dynamically choose their install path.
###  John Wrobel        02/05/03              80370
###  Added support for SDD output changes for Lodestone
###   Matthew Ward           17-March-2003                82204
###     Removed spaces in the INSTALL = CLI_install_directory
###     line.
###  John Wrobel         14-April-2003        75752
###     rsInquiryHP.exe causing core dump because of incorrect data
###     being passed to it.  Also corrected output of diskname
###  Eric Shell              17-Sept-2003                 89430
###     Re-included two export statements for INSTALLDPO and
###     INSTALLSDD.
###  Eric Shell              27-Jan-2004                  93941
###     For HP OS, allow versions B.11.XX
###
###--------------------------------------------------------------------#
###  Modifier               Date                          Change ID
###--------------------------------------------------------------------#
###  Randy Tung           09/11/2004                      110163
###      Initial version
###  Randy Tung           09/23/2004                      111712
###      Adding/enabling support for Liunx
###  Randy Tung           09/23/2004                      111714
###      Adding/enabling support for HP-UX
###  Randy Tung           09/30/2004                      111713
###      Adding/enabling support for SUN
###  Randy Tung           11/03/2004                      119203
###      Adding/enabling support for Tru64
### Randy Tung            10-14-2004                      119211
###      Modify "lshostvol" VolID output from MTMS to MTS for HP-UX
### Randy Tung            11-20-2004                      119209
###      Modify "lshostvol" VolID output from MTMS to MTS for Sun
### Randy Tung            11-20-2004                      119208
###      Modify "lshostvol" VolID output from MTMS to MTS for AIX
### Randy Tung            03-04-2005                      139536
###      Modify INSTALL statement to use /opt/ibm/dscli/bin 
###      instead of  $CLI_install_directory/bin
### Randy Tung            03-16-2005                      140882
###      Modify "lshostvol" 2105 serial number output format (Aix)
### Randy Tung            03-24-2005                      143602
###      Modify "lshostvol" 2105 serial number output format (Sun)
### Randy Tung            03-24-2005                      143604
###      Modify "lshostvol" 2105 serial number output format (Tru64)
### Randy Tung            03-24-2005                      151164
###      lshostvol don't see any attached volumes under AIX 5.2
### Randy Tung            07-08-2005                      150708
###      Remove the extra "bin" subdir from the Linux statements
### Satoru Nakamura       09-06-2006                      187663
###      Invalid volumeID was shown for unlabeled volume under SUN
### Satoru Nakamura       12-22-2006                      193901
###      Supported AIX MPIO without SDD/SDDPCM environment.
###      Corrected Volume ID format for SUN/Solaris.
### Dale/Sam              06-04-2008                      211235
###      Improve performance for AIX by using 'lscfg -pv' and awk.
### Ming LM Luo           12-26-2008                      227163
###      For HP-UX OS, add support for versions B.11.3X.
### Ming Luo              06-11-2009                      227805
###      Change the "Command Line Interface" string to 
###      "lshostvol command" which is more accurate in expression.
### Dale/Ming LM Luo      05-05-2009                      246418
###      For HP-UX OS, add support for B.11.3X 'agile' mode.
### Dale/Xu Dong Yan      08-23-2010                      248701
###      Improve performance for Solaris by using 'luxadm' and awk.
###--------------------------------------------------------------------#
### End of PROLOG


#--------------------------------------------------------------------#
# Initialization
#--------------------------------------------------------------------#
OS=`uname | cut -c 1-3`
NOHEADER=
DATAFILE=`date | awk '{print "/tmp/"$2"."$3"."$4".lshostvol.datapath"}'`
SHOWVPATHFILE=`date | awk '{print "/tmp/"$2"."$3"."$4".lshostvol.showvpath"}'`
MAPFILE=`date | awk '{print "/tmp/"$2"."$3"."$4".lshostvol.maps"}'`

###-------------------------------------------------------------------#
### We use a file to save the volume names and and a file to save the serialnumbers.
### This becomes necessary as the number of volumes increases to the
### point where it exceeds the maximum # of elements in an array
### (see cmvc 46798).
### - set DISKFILE to a temporary file name of the form:
###    /tmp/xx.yy.zz.lshostvol.disks
### - remove any existing file names that may still be lying around.
###-------------------------------------------------------------------#

DISKFILE=`date | awk '{print "/tmp/"$2"."$3"."$4".lshostvol.disks"}'`

export TMP1=/tmp/lshostvol.tmp1
export TMP2=/tmp/lshostvol.tmp2

rm -rf $TMP1 $TMP2 /tmp/*.lshostvol.datapath /tmp/*.lshostvol.showvpath
rm -rf $DISKFILE  ### /211235/

#--------------------------------------------------------------------#
# Look for options
#--------------------------------------------------------------------#
while getopts "n" opt; do
   case $opt in
      n  ) NOHEADER=1
   esac
done
shift $(($OPTIND - 1))


#--------------------------------------------------------------------#
# Setting up INSTALL variable
#--------------------------------------------------------------------#
### 75956 82204
export INSTALL=/opt/ibm/dscli/bin  ### /139536/

### 89430
export INSTALLDPO=/opt/IBMdpo/bin
export INSTALLSDD=/opt/IBMsdd/bin

#--------------------------------------------------------------------#
# Checking If DPO is installed
#--------------------------------------------------------------------#
###71500
if [[ $OS != "DYN" && $OS != "OSF" ]]; then     # ptx has multi-path/multi-port built in
   if [[ $OS = "AIX" ]]; then
      `datapath query essmap > $MAPFILE 2>/dev/null`
      `datapath query device > $DATAFILE 2>/dev/null`
   else
      ###Start 80370
      ###There are two possible default install directories
      `$INSTALLSDD/datapath query essmap > $MAPFILE 2>/dev/null`
      `$INSTALLSDD/datapath query device > $DATAFILE 2>/dev/null`
      RC=$?
      if [[ $RC -ne 0 ]]; then
         `$INSTALLDPO/datapath query essmap > $MAPFILE 2>/dev/null`
         `$INSTALLDPO/datapath query device > $DATAFILE 2>/dev/null`
      fi
      ###End 80370
   fi

   RC=$?
   if [[ $RC -eq 0 ]]; then
      if [[ -s $DATAFILE && -s $MAPFILE ]];then
         ### 76636
         if [[ $OS = "AIX" || $OS = "HP-" || $OS = "Lin" ]]; then 
            if [[ -z $NOHEADER ]]; then
               $INSTALL/lshostvolSDD.sh -f $DATAFILE -j $MAPFILE
            else
               $INSTALL/lshostvolSDD.sh -f $DATAFILE -j $MAPFILE -n
            fi
         elif [[ $OS = "Sun" ]]; then
            ###80370
            `$INSTALLSDD/showvpath > $SHOWVPATHFILE 2>/dev/null`
            RC=$?
            if [[ $RC -ne 0 ]]; then 
               `$INSTALLDPO/showvpath > $SHOWVPATHFILE 2>/dev/null`  
            fi
            ###80370
            if [[ -z $NOHEADER ]]; then
               $INSTALL/lshostvolSDD.sh -f $DATAFILE -i $SHOWVPATHFILE
            else
               $INSTALL/lshostvolSDD.sh -f $DATAFILE -i $SHOWVPATHFILE -n
            fi
         fi
         rm -rf $DATAFILE $SHOWVPATHFILE $MAPFILE
         exit 0
      fi
   fi
   rm -rf $DATAFILE $SHOWVPATHFILE $MAPFILE
fi

##-------------------------------------------------------------------#
## AIX specific code ### /211235/
##-------------------------------------------------------------------#
if [[ $OS = "AIX" ]]; then

   ##-------------------------------------------------------------------#
   ## Collect device information
   ##-------------------------------------------------------------------#
   `lscfg -pv | sed "s/\./ /g" >$TMP2 2>/dev/null`

   ##-------------------------------------------------------------------#
   ## Determine if hdisk is connected to system
   ##-------------------------------------------------------------------#
   
awk 'BEGIN  { DSK=""; MFR=""; TYP=""; SN=""; LSS=""; VOL=""; Z1 = ""; CNT=0 }
    /hdisk/         {   DSK = $1;
                        CNT = 2;                        # CNT == ?, record hdr
                    }
    /Machine Type/  {   if (CNT != 0) {                 # in record body?
                            TYP = substr( $5,1,4 );
                            if ( TYP!="2105" && TYP!="2107" && TYP!="1750" ) {
                                TYP = "";               # limit typ to these 3  
                            }
                        }
                    }
    /Serial Number/ {   if (CNT != 0) { SN  = $3; } }
    /Manufacturer/  {   if (CNT != 0) { MFR = $2; } }
    /(Z1)/          {   if (CNT != 0) { Z1  = $4; } }
    /^$/            {   if (CNT == 0) {                 # blank line
                            ;                           # CNT == 0, not in record
                        } else if (CNT == 2) {          # CNT == 2, record body
                            CNT = 1;
                        } else if ( length(TYP) != 0 ) {# CNT == 1, print record
                            CNT = 0;
                            if ( TYP == "2105" ) {
                                LSS = "1" substr( SN, 1, 1 );
                                VOL = substr( SN, 2, 2 );
                                SN  = substr( SN, 4, 5 );
                            } else if ( TYP == "2107" || TYP == "1750" ) {
                                ## 2107/1750 has different ways to retrieve
                                ## LSSDN other than 2105. Need to either issue
                                ## SCSI Inquiry command or parse lscfg command
                                ## outputs to acquired the necessary data!
                                LSS = substr( SN, 8,  2 );
                                VOL = substr( SN, 10, 2 );
                                if (length(VOL) == 0) {
                                    ### 193901
                                    ## Under MPIO without SDD/SDDPCM environment
                                    ## the second digit and volume# (2 digits) 
                                    ## appear in Z1 field.
                                    VOL = substr( Z1, 1, 3 );
                                }   
                                SN  = substr( SN, 1, 7 );
                            }
                            printf( "%-8s\t%s.%s-%s/%s%s\n", DSK, MFR, TYP, 
                                                             SN, LSS, VOL);
                        }
                    }' $TMP2 >$TMP1 2>"/dev/null"
                    
    if [[ ! -s $TMP1 ]]; then                           # error, no awk output
        COUNT=0
    else
        COUNT=`cat $TMP1 | wc -l`                       # count number of disks
        cat $TMP1 | sort -k 1.6n >$DISKFILE             # sort so '2' < '19'
    fi
fi

##-------------------------------------------------------------------#
## Sun specific code
##-------------------------------------------------------------------#
if [[ $OS = "Sun" ]]; then
   HELPFILE2105=`date | awk '{print "/tmp/"$2"."$3"."$4".lshostvol2105.help"}'`
   HELPFILE2107=`date | awk '{print "/tmp/"$2"."$3"."$4".lshostvol2107.help"}'`
   rm -rf $HELPFILE2105 $HELPFILE2107

   ##-------------------------------------------------------------------#
   ## Collect device information
   ##-------------------------------------------------------------------#
   echo "disk\n0\nquit" >$TMP1
   format -f $TMP1 -l $TMP2 1>/dev/null 2>/dev/null

   ##-------------------------------------------------------------------#
   ## Collect device file names
   ##-------------------------------------------------------------------#
   ## TEMP2105DISKS and TEMP2107DISKS contain disk names
   TEMP2105NAMES=`cat $TMP2 | awk '/IBM-2105/ { print $2 }' | sed "s/\.//g"`
   TEMP2107NAMES=`cat $TMP2 | awk '/IBM-2107/ || /IBM-1750/ { print $2 }' | sed "s/\.//g"`

   COUNT2105=0
   COUNT2107=0
   for DISKNAME in $TEMP2105NAMES; do
      echo " $DISKNAME" >> $HELPFILE2105
      COUNT2105=$(($COUNT2105 + 1))
   done
   for DISKNAME in $TEMP2107NAMES; do
      echo " $DISKNAME" >> $HELPFILE2107
      COUNT2107=$(($COUNT2107 + 1))
   done

   ##-------------------------------------------------------------------#
   ## Collect 2105/2107/1750 serial numbers
   ##-------------------------------------------------------------------#
   echo "scsi\ninquiry" >$TMP1

   ###68207 do not continue if no 2105, 2107 or 1750 volumes exist
   if [[ $COUNT2105 -ne 0 ]]; then
      for DISKNAME in $TEMP2105NAMES; do
         format -e -f $TMP1 $DISKNAME 1>/dev/null 2>$TMP2
         X="cat $TMP2 |
               awk 'BEGIN { FOUND=0 } { if (FOUND > 0) { print \$0; exit } } /2105/ { FOUND=1 }' |
               awk '{ print \$17 }' |
               cut -c5-12"
         Y="cat $TMP2 |
               awk '/2105/ { print \$17 }' |
               cut -c1-4"
         Z="cat $TMP2 |
               awk '/2105/ { print \$17 }' |
               cut -c5-7"
         DISKS2105=`eval $X`
         TYPE=`eval $Y`
         MODEL=`eval $Z`
         LSS=`print $DISKS2105 | cut -c1`
         VOL=`print $DISKS2105 | cut -c2-3`
         DISK2105=`print $DISKS2105 | cut -c4-8`    ### 143602
         ### 19209 MTMS -> MTS
         DISKS="IBM.$TYPE-$DISK2105/1$LSS$VOL"      ### 193901
         echo  " $DISKNAME \t\t $DISKS " >> $DISKFILE
      done
      ### 68207
   fi
   
   if [[ $COUNT2107 -ne 0 ]]; then
      # Use different command for 2107&1750 drives in different versions of 
      # Solaris, as "luxadm" can only be supported in Solaris version 8 and
      # onwards.
      VER=`uname -a | sed 's/\./ /g' | awk '{print $4}'`
      if (( $VER < 8 )); then
         for DISKNAME in $TEMP2107NAMES; do
            format -e -f $TMP1 $DISKNAME 1>/dev/null 2>$TMP2
            X="cat $TMP2 |
                  awk 'BEGIN { FOUND=0 } { if (FOUND > 0) { print \$0; exit } } /2107/ || /1750/ { FOUND=1 }' |
                  awk '{ print \$17 }' |
                  cut -c5-15"
            Y="cat $TMP2 |
                  awk '/2107/ || /1750/ { print \$17 }' |
                  cut -c1-4"
            Z="cat $TMP2 |
                  awk '/2107/ || /1750/ { print \$17 }' |
                  cut -c5-7"
            DISKS2107=`eval $X`
            TYPE=`eval $Y`
            MODEL=`eval $Z`
            SERIAL2107=`print $DISKS2107 | cut -c1-7`
            LSSVOL=`print $DISKS2107 | cut -c8-11`
            ### 19209 MTMS -> MTS
            DISKS="IBM.$TYPE-$SERIAL2107/$LSSVOL"      ### 193901
            echo  " $DISKNAME \t\t $DISKS " >> $DISKFILE
         done
         ### 68207
         let COUNT=$COUNT2105+$COUNT2107
      else
         luxadm probe >$TMP2 2>/dev/null
         rm -rf $TMP1
         for i in `grep Logical $TMP2 | cut -d: -f 2`; do
             echo $i '\t%%start%%' | sed "s/\// /g" >> $TMP1 2>/dev/null
             luxadm inquiry $i >> $TMP1 2>/dev/null
         done
         awk 'BEGIN { DSK=""; TYP=""; SN=""; LSS=""; VOL=""; CNT=0 }
             /%%start%%/  {  DSK = substr( $3, 1, index($3, "s")-1 );
                             CNT = 1;
                          }
             /Product/    {  if (CNT != 0) {
                                TYP = substr( $2, 1, 4 );
                             }
                          }
             /Serial/     {  if (CNT != 0) {
                                if ( TYP == "2107" || TYP == "1750" ) {
                                   SN = substr( $3, 1, 7 );
                                   LSS= substr( $3, 8, 2 );
                                   VOL= substr( $3, 10, 2);
                                   printf ( " %s \t\t IBM.%s-%s/%s%s\n", DSK, TYP, SN, LSS, VOL );
                                }
                                CNT = 0;
                             }
                          }' $TMP1 >$TMP2 2>/dev/null
         if [[ ! -s $TMP2 ]]; then
            COUNT=$COUNT2105
         else
            COUNT=$((`cat $TMP2 | wc -l`+$COUNT2105))
            sort -k 1.2nb,1.19b -k 1.21nb $TMP2 >> $DISKFILE 2>/dev/null
         fi
      fi
   fi
   rm -rf $HELPFILE2105 $HELPFILE2107
fi

##-------------------------------------------------------------------#
## HP specific code
##-------------------------------------------------------------------#
if [[ $OS = "HP-" ]]; then

   ##-------------------------------------------------------------------#
   ## Determine version information
   ##-------------------------------------------------------------------#
   OSVERSION=`uname -a | awk '{print $3}'`
   OSMAJOR=`print $OSVERSION | awk -F\. '{ print $2 }'`
   OSMINOR=`print $OSVERSION | awk -F\. '{ print $3 }'`
   SCANOPTS="fnC"                      # ioscan parameters for legacy naming
   SEDOPTS="s/dsk/rdsk/g"              # sed parameters for legacy naming

   if (( $OSMAJOR == 11 )); then
      if (( $OSMINOR >= 30 )); then    # HP-UX 11iv3 or later
         LEGACY=`insf -L -v |
            awk 'BEGIN { FOUND=0 } /Legacy mode is enabled/ { FOUND=1 } END { print FOUND }'`
         if (( $LEGACY == 0 )); then   # legacy mode off or not available?
            SCANOPTS="N$SCANOPTS"      # "N" forces new "agile" device naming
	    SEDOPTS="s/disk/rdisk/"    # sed parameters for agile naming
         fi
      fi
      export INQUIRY=$INSTALL/rsInquiryHP11.exe
#      export INQUIRY=./rsInquiryHP11.exe
   elif [[ $OSVERSION = "B.10.20" ]]; then
      export INQUIRY=$INSTALL/rsInquiryHP10.exe
   else
      echo "Command Line Interface is not supported for HP-UX Version $OSVERSION"
      exit 80
   fi

   ##-------------------------------------------------------------------#
   ## Collect device information
   ##-------------------------------------------------------------------#

   ioscan -$SCANOPTS disk >$TMP2 2>/dev/null

   ##-------------------------------------------------------------------#
   ## Collect device file names
   ##-------------------------------------------------------------------#
   ### 119211 starts
   TEMP2105=`cat $TMP2 |
                  awk 'BEGIN { FOUND=0 } { if (FOUND==1) { print $1; FOUND=0 }} / 2105/ { FOUND=1 }' |
                  awk '{ print $1 }' | sed "$SEDOPTS"`
   TEMP2107=`cat $TMP2 |
                  awk 'BEGIN { FOUND=0 } { if (FOUND==1) { print $1; FOUND=0 }} / 2107/ { FOUND=1 }' |
                  awk '{ print $1 }' | sed "$SEDOPTS"`
   TEMP1750=`cat $TMP2 |
                  awk 'BEGIN { FOUND=0 } { if (FOUND==1) { print $1; FOUND=0 }} / 1750/ { FOUND=1 }' |
                  awk '{ print $1 }' | sed "$SEDOPTS"`
   TEMPNAMES="$TEMP2105 $TEMP2107 $TEMP1750"
   ### 119211 ends
   COUNT=0

   ##-------------------------------------------------------------------#
   ## Collect 2105 serial numbers
   ##-------------------------------------------------------------------#

   for DISKNAME in $TEMPNAMES; do
      ###75752 - Prevent core-dump by checking for correct input to c-code  
      if [[ $DISKNAME != "disk" ]]; then
         SNO=`$INQUIRY  $DISKNAME -n`
         RC=$?
         if [[ $RC -eq 0 ]]; then
            DISKNAMES=`print $DISKNAME | awk -F\/ '{ print $4 }'`
            DISKS=$SNO
            ###75752 - Output $DISKNAMES not $DISKNAME
            echo  " $DISKNAMES \t\t $DISKS" >> $DISKFILE
            COUNT=$(($COUNT + 1))
         fi
      fi
      ###75752 - End
   done
fi

##-------------------------------------------------------------------#
## DYNIX/ptx specific code
##-------------------------------------------------------------------#
if [[ $OS = "DYN" ]]; then

   ##-------------------------------------------------------------------#
   ## Collect all disks defined to system
   ##-------------------------------------------------------------------#
   TEMPDISKS=`(dumpconf -md | awk -F":" '$2 == "sd"  { print $1 }' | sort | uniq) 2>/dev/null`

   ##-------------------------------------------------------------------#
   ## Determine if hdisk is connected to system
   ##-------------------------------------------------------------------#
   COUNT=0

   for DISKNAME in $TEMPDISKS; do
      DI=`diskid $DISKNAME`
      TYPE=`print $DI | awk '/2105/ {print substr($0, index($0, "2105"), 4)}'`
      if [[ $TYPE = "2105" ]]; then
         TMPSN=${DI#*serial # }
         ### remove newline after disks 58685
         DISKS=`print ${TMPSN% capacity*}  | awk '{print $1 }'`
         echo  " $DISKNAME \t\t $DISKS" >> $DISKFILE
         COUNT=$(($COUNT + 1))
      fi
   done
fi


##-------------------------------------------------------------------#
## Linux specific code
##-------------------------------------------------------------------#

if [[ $OS = "Lin" ]]; then

   ##-------------------------------------------------------------------#
   ## Collect all disks defined to system and determines if disks
   ## connect to the system
   ##-------------------------------------------------------------------#
   ### 150708
   MACHINE=`uname -m`
   if [[ $MACHINE = "ppc64" ]]; then
      $INSTALL/rsInquiryLinux-P.exe -n >$DISKFILE   ### /139536/
   else
      $INSTALL/rsInquiryLinux.exe -n >$DISKFILE   ### /139536/
   fi
   RC=$?
   COUNT=0;
   if [[ $RC = 0 && -s $DISKFILE  && -a $DISKFILE ]]; then
       COUNT=1;
   fi
fi


##-------------------------------------------------------------------#
## Tru64 specific code
##-------------------------------------------------------------------#
if [[ $OS = "OSF" ]]; then
   OSVERSION=`uname -a | awk '{print $3}' | cut -c 1-2`

   if [[ $OSVERSION = "V5" ]]; then
      COUNT=0
      ## Handle 2105 Volumes
      TEMPDISKIDS=`hwmgr -view devices | egrep '2105' | awk '{ print $1 }' | sed "s/://g"`
      for DISKID in $TEMPDISKIDS; do
         DISKIDINFO=`hwmgr -get attribute -id $DISKID | egrep 'dev_base_name|serial_number'`
         DISKMMINFO=`hwmgr -get attribute -id $DISKID | egrep 'model|manufacturer'`
         DISKNAME=`echo $DISKIDINFO | awk '{ print $3}'`
         DISKSER=
         DISKSER=`echo $DISKIDINFO | awk '{print $8}' | cut -c 1-8`
         if [[ -z $DISKSER ]]; then
            ##SCSI attached volumes
            DISKSER=`echo $DISKIDINFO | awk '{print $6}' | cut -f8 -d\-`
            DISKSER=$DISKSER`echo $DISKIDINFO | awk '{print $6}' | cut -f9 -d\-`
         fi
         MODEL=`echo $DISKMMINFO | awk '{print $3}' | cut -c 1-4`
         MANUFACTURER=`echo $DISKMMINFO | awk '{ print $6}'`
         2105V5LSSVID=`echo $DISKSER | cut -c 1-3`                                         ###143604
         DISKSER=`echo $DISKSER | cut -c 4-8`                                              ###143604
         echo  " $DISKNAME \t\t $MANUFACTURER.$MODEL-$DISKSER/1$2105V5LSSVID" >> $DISKFILE ###143604
         COUNT=$(($COUNT + 1))
      done
      TEMPDISKIDS=`hwmgr -view devices | egrep '2107|1750' | awk '{ print $1 }' | sed "s/://g"`
      for DISKID in $TEMPDISKIDS; do
         DISKIDINFO=`hwmgr -get attribute -id $DISKID | egrep 'dev_base_name|serial_number'`
         DISKMMINFO=`hwmgr -get attribute -id $DISKID | egrep 'model|manufacturer'`
         DISKNAME=`echo $DISKIDINFO | awk '{ print $3}'`
         DISKSER=
         DISKSER=`echo $DISKIDINFO | awk '{print $8}' | cut -c 1-8`
         if [[ -z $DISKSER ]]; then
            ##SCSI attached volumes
            DISKSER=`echo $DISKIDINFO | awk '{print $6}' | cut -f8 -d\-`
            DISKSER=$DISKSER`echo $DISKIDINFO | awk '{print $6}' | cut -f9 -d\-`
         fi
         LSSVID=`echo $DISKSER | awk '{print $1}' | cut -c 8-11`
         DISKSER=`echo $DISKSER | awk '{print $1}' | cut -c 1-7`
         MODEL=`echo $DISKMMINFO | awk '{print $3}' | cut -c 1-4`
         MANUFACTURER=`echo $DISKMMINFO | awk '{ print $6}'`
         echo  " $DISKNAME \t\t $MANUFACTURER.$MODEL-$DISKSER/$LSSVID" >> $DISKFILE
         COUNT=$(($COUNT + 1))
      done
   fi
   if [[ $OSVERSION = "V4" ]]; then
      HELPFILE=`date | awk '{print "/tmp/"$2"."$3"."$4".lshostvol.help"}'`
      rm -rf $HELPFILE
      `ls /dev/rrz*c > $HELPFILE`
      exec 0<$HELPFILE
      while read TEMPDISKS; do
         DISKIDINFO=`scu -f $TEMPDISKS show inq 2>/dev/null | grep -E "Vendor Identification: IBM |Product Identification: 2105|Vendor Specific Data"`
         VENDOR=`echo $DISKIDINFO | awk '{print $3}'`
         PRODUCT=`echo $DISKIDINFO | awk '{print $6}' | cut -c 1-4`
         if [[ $VENDOR = IBM ]]; then
                                                                                        ###71621
             if [[ $PRODUCT = "2105" ]]; then
                TEMPDISKS=`echo $TEMPDISKS | sed "s/\/dev\///g"`
                                                                                        ###71621
                DISKIDINFO=`echo $DISKIDINFO | awk '{print $19}'  | sed "s/\"//g"`
                2105V4LSSVID=`echo $DISKIDINFO | cut -c 1-3`                            ###143604                 
                DISKIDINFO=`echo $DISKIDINFO | cut -c 4-8`                              ###143604 
                echo "$TEMPDISKS \t\t IBM.2105-$DISKIDINFO/1$2105V4LSSVID" >> $DISKFILE ###143604 
                COUNT=$(($COUNT + 1))
             fi
             if [[ $PRODUCT = "2107" || $PRODUCT = "1750" ]]; then
                TEMPDISKS=`echo $TEMPDISKS | sed "s/\/dev\///g"`
                DISKIDINFO=`echo $DISKIDINFO | awk '{print $19}'  | sed "s/\"//g"`
                SERIAL=`echo $DISKIDINFO | cut -c 1-7`
                LSSVID=`echo $DISKIDINFO | cut -c 8-11`
                if [[ $PRODUCT = "2107" ]]; then
                   echo "$TEMPDISKS \t\t IBM.2107-$SERIAL/$LSSVID" >> $DISKFILE
                else
                   echo "$TEMPDISKS \t\t IBM.1750-$SERIAL/$LSSVID" >> $DISKFILE
                fi
                COUNT=$(($COUNT + 1))
             fi
         fi
      done
      rm -rf $HELPFILE
   fi
fi

##-------------------------------------------------------------------#
## Display infomation
##-------------------------------------------------------------------#
LINE=0

if [[ -z $NOHEADER ]]; then
   if [[ $COUNT -eq 0 ]]; then
      echo "No 2105, 2107 or 1750 volumes found"
      exit 13
   fi
   ###60708 substitute \t with a real tab
   if [[ $OS = "Lin" ]]; then   
      echo "Device Name Volume ID"
      echo "----------- --------------------------------"
   else
      echo "Device Name\t   Volume ID"
      echo "-----------\t--------------------------------"
   fi
else
   if [[ $COUNT -eq 0 ]]; then
      exit 13
   fi
fi

if [[ -z $NOHEADER ]]; then
   exec 0<$DISKFILE
   while read DISKNAMES DISKS; do
      if [[ $DISKS = "" ]]; then
           DISKS='NoSerialNumberFound'
      fi
      if [[ $OS = "AIX" ]]; then
         DISK=$DISKNAMES
         if [[ ${#DISK} > 6 ]]; then
            echo " $DISKNAMES\t   $DISKS"
         else
            echo " $DISKNAMES\t\t   $DISKS"
         fi
      else
         DISK=$DISKNAMES
         if [[ ${#DISK} > 6 ]]; then
            printf " %s %s\n" $DISKNAMES $DISKS
         else
            printf " %s     %s\n" $DISKNAMES $DISKS
         fi
      fi
   done
else
   cat $DISKFILE
fi
rm -rf $DISKFILE

##-------------------------------------------------------------------#
## Clean-up
##-------------------------------------------------------------------#
rm -rf $TMP1 $TMP2

##-------------------------------------------------------------------#
## Quit
##-------------------------------------------------------------------#
exit 0