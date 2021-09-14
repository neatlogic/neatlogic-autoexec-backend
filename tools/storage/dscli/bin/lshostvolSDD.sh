#!/bin/bash

##-------------------------------------------------------------------#
## %PS
##    
## Licensed Internal Code - Property of IBM
##    
## 2105/2107 Licensed Internal Code
##    
## (C) Copyright IBM Corp. 1999, 2006 All Rights Reserved.
##    
## US Government Users Restricted Rights - Use, duplication or
## disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
## %EPS
##
## COMPONENT_NAME (RAS WUI)
##
## Function: lshostvolSDD.sh
##
##--------------------------------------------------------------------#
##
## Filename: lshostvolSDD.sh
##
## Subsystem: RAS WUI
##
## Input:       lshostvolSDD.sh -f inputfile -i inputfile2 
##                              -j inputfile3 -n
##
## Description: querys the mapping of host volume names to 2107, 2105
##              and 1750 volume IDs
##
###-------------------------------------------------------------------#
### Legacy Change History:
###-------------------------------------------------------------------#
###  John Wrobel & 
###  Ramandeep Kaur        08/01/2000                       
###      Initial version
###  Ramandeep Kaur        08/17/2000                      39254
###      Deleted the blank line from the output 
###  Ruth E. Azevedo       08/28/2000                      39885 
###      AIX parse of datapath query no dependable on field length
###  Susanne Lukas &       11-14-2000                      43080
###  Ramandeep Kaur
###      Included check to find string DEV or Dev in Sun output file 
###  Susanne Lukas         03-15-2001                      48392
###      Creating a file containin the serial numbers and the volume names  
###  Ramandeep Kaur         05-29-2001                      51827
###      Modified the prolog line and comments line to start
###      with ###
###  John Wrobel           12/17/01                        62966
###  Updated script to run with SDD output change
###  Amy Therrien          03/18/02                        67087
###      NOTE TO REMAPPER: this defect is used to merge the version
###      of rsList2105DPO.sh from pprc/ into pprc/CLI/GENERIC and then
###      remove the duplicate in pprc/ but keep this version in 
###      pprc/CLI/GENERIC active
###  John Wrobel           06/07/02                        71500
###  Added support for Linux.
###  Amy Therrien          09/22/02                        76078
###      Remove Linux support/remove 71500
###  Amy Therrien          10/07/02                        76636
###      Put DPO call for Linux here
###  John Wrobel           02/05/03                        80370
###  Added support for SDD output changes for Lodestone
###  John Wrobel       04/12/04                        99635
###  Modified script to use /bin/bash instead of /usr/bin/bash
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
### Randy Tung            10-14-2004                      119211
###      Modify "lshostvol" VolID output from MTMS to MTS for HP-UX
### Randy Tung            11-20-2004                      119209
###      Modify "lshostvol" VolID output from MTMS to MTS for Sun
### Randy Tung            11-20-2004                      119208
###      Modify "lshostvol" VolID output from MTMS to MTS for AIX
### Randy Tung            03-16-2005                      140882
###      Modify "lshostvol" 2105 serial number output format (AIX)
### Randy Tung            03-24-2005                      143602
###      Modify "lshostvol" 2105 serial number output format (Sun)
### Randy Tung            07-08-2005                      150708
###      Remove the extra "bin" subdir from the Linux statements
### Dale Anderson         02-28-2006                      172809
###      Modify INSTALL statement to use /opt/ibm/dscli/bin 
###      instead of $CLI_install_directory/bin
###--------------------------------------------------------------------#
### End of PROLOG

DISKFILE=`date | awk '{print "/tmp/"$2"."$3"."$4".lshostvolSDD.disks"}'`

rm -rf /tmp/*.lshostvolSDD.temp
rm -rf DISKFILE

#--------------------------------------------------------------------#
# Initialization
#--------------------------------------------------------------------#
Firsttime=0
OS=`uname | cut -c 1-3`
NOHEADER=

#--------------------------------------------------------------------#
# Setting up INSTALL variable
#--------------------------------------------------------------------#
### 75956 82204 172809
export INSTALL=/opt/ibm/dscli/bin

#--------------------------------------------------------------------#
# Get options
#--------------------------------------------------------------------#
while getopts "f:i:j:n" opt; do
   case $opt in
      f ) FILE=$OPTARG;;
      i ) FILE_TWO=$OPTARG;;
      j ) FILE_THREE=$OPTARG;;
      n ) NOHEADER=1
   esac
done

#--------------------------------------------------------------------#
# Function printoutput 
#--------------------------------------------------------------------#
function printoutput {
   LONGSPACES="    "
   SHORTSPACES="   "
   LONGINDENT="                        "
   SHORTINDENT="                       "
   if [[ -z $NOHEADER ]]; then
      if [[ $Firsttime -eq 0 ]]; then
         printf " Vpath Name    Volume ID                 Device Names\n"
         printf "------------  ----------------------    ------------------------------\n"
         Firsttime=1
      fi
      if [[ ${#NAME} > 8 ]]; then
        printf " %s    " $NAME
      elif [[ ${#NAME} > 7 ]]; then
        printf " %s     " $NAME
      elif [[ ${#NAME} > 6 ]]; then
        printf " %s      " $NAME 
      elif [[ ${#NAME} > 5 ]]; then
        printf " %s       " $NAME
      fi
      if [[ ${#SERIAL} = 8 ]]; then
         INDENT=$SHORTINDENT;
         SPACES=$SHORTSPACES;
      else
         INDENT=$LONGINDENT;
         SPACES=$LONGSPACES;
      fi
      if [[ $count -ge 0  && -n $TYPE && -n $SERIAL ]]; then
         # *119209* MTMS -> MTS: 
         print "IBM.$TYPE-$SERIAL/$newLSS$newVOL$SPACES" ${DSK[0]} ${DSK[1]} ${DSK[2]} ${DSK[3]} ${DSK[4]} ${DSK[5]} ${DSK[6]} ${DSK[7]}
      fi
      if [[ $count -gt 8 ]]; then
         print $INDENT ${DSK[8]} ${DSK[9]} ${DSK[10]} ${DSK[11]} ${DSK[12]} ${DSK[13]} ${DSK[14]} ${DSK[15]}
      fi
      if [[ $count -gt 16 ]]; then
         print $INDENT ${DSK[16]} ${DSK[17]} ${DSK[18]} ${DSK[19]} ${DSK[20]} ${DSK[21]} ${DSK[22]} ${DSK[23]}
      fi
      if [[ $count -gt 24 ]]; then
         print $INDENT ${DSK[24]} ${DSK[25]} ${DSK[26]} ${DSK[27]} ${DSK[28]} ${DSK[29]} ${DSK[30]} ${DSK[31]}
      fi

   else
      if [[ -n $NAME && -n $SERIAL ]]; then
         let IDX=0
         DSKNAMES=`print ""`
         while [[ $IDX -lt $count ]]; do
            DSKNAMES=`printf "%s%s" $DSKNAMES ${DSK[$IDX]}`
            let IDX=$IDX+1
            if [[ $IDX -lt $count ]]; then
               DSKNAMES=`print "$DSKNAMES,"`
            fi
         done
         DSKNAME=`print "$DSKNAMES\tIBM.$TYPE-$SERIAL/$newLSS$newVOL\t$NAME"`
         echo $DSKNAME >> $DISKFILE
         cat $DISKFILE
         rm -rf $DISKFILE
      fi
   fi
   count=0
   set -A DSK
}

##-------------------------------------------------------------------#
## Linux specific code
##-------------------------------------------------------------------#
###76636
if [[ $OS = "Lin" ]]; then
   ### 150708
   MACHINE=`uname -m`
   if [[ $MACHINE = "ppc64" ]]; then
      if [[ -z $NOHEADER ]]; then
         $INSTALL/wbCsLinuxDPO-P.exe $FILE >> $DISKFILE
      else
         $INSTALL/wbCsLinuxDPO-P.exe $FILE -n >> $DISKFILE
      fi
   else
      if [[ -z $NOHEADER ]]; then
         $INSTALL/wbCsLinuxDPO.exe $FILE >> $DISKFILE
      else
         $INSTALL/wbCsLinuxDPO.exe $FILE -n >> $DISKFILE
      fi
   fi
   cat $DISKFILE
   rm -rf $FILE $DISKFILE
fi


##-------------------------------------------------------------------#
## AIX and HP specific code
##-------------------------------------------------------------------#
###71500 
if [[ $OS = "AIX" ||  $OS = "HP-" ]]; then 
   Index=`cat $FILE | wc -l`
   Index_map=`cat $FILE_THREE | wc -l`
   exec 3< $FILE         
   read -u3 line
   exec 4< $FILE_THREE
   read -u4 line_map

   Field=`print $line | awk '{ print $1;}'`
   Field_map=`print $line_map | awk '{ print $1;}'`

   Counter=0
   Counter_map=0
   count=0
   found_map=0

   ###80370
   LODESTONEFOUND=0;

   while [[ $Counter -ge 0 && $Counter -le $Index ]]; do
      if [[ $Field = "" && $Counter -ne $Index ]]; then
         read -u3 line
         let Counter=$Counter+1
         Field=`print $line | awk '{ print $1;}'`
      fi
      if [[ $Field = "Total" ]]; then
         read -u3 line
         let Counter=$Counter+1
         Field=`print $line | awk '{ print $1;}'`
      fi

      if [[ $Field = "Dev#:" || $Field = "DEV#:" || $Counter -eq $Index ]]; then
         if [[ $Counter -eq $Index ]]; then
            let Counter=$Counter+1
         fi   
         ###80370 - Do not print output for LodeStone machine types
         if [[ $count -ge 0 ]]; then
            if [[ $LODESTONEFOUND -ne 0 ]]; then
               count=0
            else     
               printoutput
            fi 
         fi
         LODESTONEFOUND=0
         ## MACHINE TYPE ##
         TYPE=`print $line | awk '{ print substr($7,1,4)}'`
         ###80370 - Check to see if machine type = LodeStone
         if [[ $TYPE = "2105" || $TYPE = "2145" || $TYPE = "2107" || $TYPE = "1750" ]]; then
            if [[ $TYPE = "2145" ]]; then
               LODESTONEFOUND=1
            fi
            ## MODEL NUMBER ##
            MODEL=`print $line | awk '{ print substr($7,5,7)}'`
            ## VPATH ##
            NAME=`print $line | awk '{ print $5;}'`
            SERIAL=`print $line | awk '{ print $9;}'`
            read -u3 line
            let Counter=$Counter+1
            ### cmvc 62966 next 5 lines
            SDD=`print $line | awk '{ print $1;}'`
            ###80370-Check the location of the 'Serial:' field
            ###Lodestone changes for SDD output put Serial on a new line b/c it is 32 chars
            ## SERIAL NUMBER ##
            if [[ $SDD = "POLICY:" || $SDD = "Policy:" ]]; then
               read -u3 line
               let Counter=$Counter+1
            ###71500, 80370   
            elif [[ $SDD = "SERIAL:" || $SDD = "Serial:" ]]; then 
               SERIAL=`print $line | awk '{ print $2;}'`
               read -u3 line
               let Counter=$Counter+1 
            fi
            ## LSS & Vol_Num ##
            ## Get LSS & Vol_Num * 119208 MTMS -> MTS
            if [[ $TYPE = "2105" ]]; then
               newLSS=`print $SERIAL | cut -c 1`
               newLSS="1$newLSS"
               newVOL=`print $SERIAL | cut -c 2-3`
               SERIAL=`print $SERIAL | cut -c 4-8`             ## 140882
            ### 119211 Added handling code for 2107 and 1750
            elif [[ $TYPE = "2107" || $TYPE = "1750" ]]; then
               newLSS=`print $SERIAL | cut -c 8-9`
               newVOL=`print $SERIAL | cut -c 10-11`
               SERIAL=`print $SERIAL | cut -c 1-7`
            fi
            found_map=0
            read -u3 line
            let Counter=$Counter+1
            read -u3 line
            let Counter=$Counter+1
            Field=`print $line | awk '{ print $1;}'`
         fi
      ## else if the first field is numeric then get the device/volume names
      elif [[ $Field -ge 0 && $Field -le 31 ]]; then  
         if [[ $OS = "AIX" ]]; then
            ### CMVC 39885, next three lines 
            TEMPDSK=`print $line | awk '{ print $2}'`
            TDSK=`print $TEMPDSK | sed "s/\// /" | awk '/scsi/ {print $2}'`
            DSK[$count]=$TDSK
         else  ## HP-UX
            DSK[$count]=`print $line | awk '{ print $3}'`
            ### 119211 Removed code to correct the VOLID output
         fi
         count=$(($count + 1))
         read -u3 line
         let Counter=$Counter+1
         Field=`print $line | awk '{ print $1;}'`
      else  ## if first field is not "numeric" or not "DEV#" then read another line
          read -u3 line
          let Counter=$Counter+1
          Field=`print $line | awk '{ print $1;}'`
      fi
   done    
   #-----------------------------------------------------------------------
   # Removing the temporary file
   #-----------------------------------------------------------------------
   rm -rf $FILE
   rm -rf $FILE_TWO
   rm -rf $FILE_THREE
fi

##-------------------------------------------------------------------#
## Sun specific code
##-------------------------------------------------------------------#
if [[ $OS = "Sun" ]]; then

   Date=`date`
   TEMPFILE=`print $Date | awk '{ print "/tmp/"$2"."$3"."$4".lshostvolSDD.temp"}'`

   ###80370-Include lines beginning with 'SERIAL:' into $TEMPFILE
   X="cat $FILE | awk '\$1 ~ /DEV#:|SERIAL:/' > $TEMPFILE"
   `eval $X`
   if [[ ! -s $TEMPFILE ]]; then
     ###80370-Include lines beginning with 'SERIAL:' into $TEMPFILE
     X="cat $FILE | awk '\$1 ~ /Dev#:|Serial:/' > $TEMPFILE"
     `eval $X`
   fi 

   Index=`cat $TEMPFILE | wc -l`

   exec 3< $TEMPFILE

   read -u3 line
   Field=`print $line | awk '{ print $1;}'`

   Counter=0

   while [[ $Counter -ge 0 && $Counter -le $Index ]]; do
      if [[ $Field = "DEV#:" || $Field = "Dev#:" || $Counter -eq $Index ]]; then
         MODEL=`print $line | awk '{ print substr($7,5,7)}'`
         TYPE=`print $line | awk '{ print substr($7,1,4)}'`
         if [[ $TYPE = "2105" || $TYPE = "2107" || $TYPE = "1750" ]]; then     
            pathWidth=`print $line | awk '{ print length($5)}'`
            lastchar=`print $line | awk '{ print substr($5,length($5))}'`
            if [[ $lastchar = "0" || $lastchar = "1" || $lastchar = "2" || $lastchar = "3" ||
                  $lastchar = "4" || $lastchar = "5" || $lastchar = "6" || $lastchar = "7" ||
                  $lastchar = "8" || $lastchar = "9" ]]; then
               NAME=`print $line | awk '{ print $5}'`
            else
               NAME=`print $line | awk '{ print substr($5,1,(length($5)-1))}'`
            fi
            if [[ $prevNAME != $NAME ]]; then
               ###Start 80370-'Serial:' field now has its own line b/c it is 32 chars for Lodestone
               SDDLevel=`print $line | awk '{ print $8;}'`
               if [[ $SDDlevel = "SERIAL:" || $SDDlevel = "Serial:" ]]; then
                  SERIAL=`print $line | awk '{ print $9;}'`
               else 
                  read -u3 line
                  let Counter=$Counter+1
                  SERIAL=`print $line | awk '{ print $2;}'`
               fi   
               ###End 80370
               ## NewName contains the vpathName
               NewNAME=`print $NAME | awk '{ print $1":"}'`
               DSKARRAY=`cat $FILE_TWO |
                             awk 'BEGIN { FOUND=0 } /'"$NewNAME"'/ { FOUND=1; FLAG=1; } /vpath/ { if (FLAG==0) { FOUND=0 }} { if (FOUND==1) { print $1; FLAG=0; }}'`
               count=0
               FIRSTDSK=0
               for DISK in $DSKARRAY; do
                  if [[ $FIRSTDSK -eq 0 ]]; then
                     FIRSTDSK=1
                  else
                     DSK[$count]=$DISK
                     count=$(($count + 1))
                  fi
               done
               if [[ $TYPE = "2105" ]]; then
                  newLSS="1`print $SERIAL | cut -c 1`"
                  newVOL=`print $SERIAL | cut -c 2-3`
                  SERIAL=`print $SERIAL| cut -c 4-8`          ### 143602
               elif [[ $TYPE = "2107" || $TYPE = "1750" ]]; then
               
                  newLSS=`print $SERIAL | cut -c 8-9`
                  newVOL=`print $SERIAL | cut -c 10-11`
                  SERIAL=`print $SERIAL| cut -c 1-7`
               fi
               printoutput
            fi
         fi
         prevNAME=$NAME
         read -u3 line
         let Counter=$Counter+1
      fi
   done


   #-----------------------------------------------------------------------
   # Removing the temporary file
   #-----------------------------------------------------------------------
   #rm -rf $TEMPFILE
fi