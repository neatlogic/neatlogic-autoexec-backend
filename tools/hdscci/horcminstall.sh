#!/bin/sh
#
# $Header: horcminstall.sh 1.00 07/04/1998 RM Copyright (c) 2000-2017, Hitachi, Ltd.
# $Header: horcminstall.sh 1.00 07/04/1998 RM Copyright (c) 2000-2017 Hewlett Packard Enterprise Development LP.
#
# Revision 1.5    31/07/12
#  Support rmawk command
# Revision 1.4    20/04/10
#  Support raidcom command
# Revision 1.3    26/07/06
#  Support raidcfg command
# Revision 1.2    03/03/06
#  Support horctakeoff command
# Revision 1.1    07/04/98
#  Initial revision

for i in horcctl paircreate pairresync pairsplit pairdisplay raidscan pairevtwait pairvolchk paircurchk pairmon horctakeover raidar raidqry horcmstart.sh horcmshutdown.sh pairsyncwait raidvchkscan raidvchkdsp raidvchkset horctakeoff raidcfg raidcom rmawk
do 
	j=/usr/bin/$i
	if [ -d $j ]
	then
		echo $j is a directory.
		exit
	elif [ ! -h $j ]
	then
		if [ ! -f $j ]
		then
			/bin/ln -s /HORCM$j $j
		else
			echo $j is not a symbolic link.
			exit
		fi
	fi
done

j=/etc/horcmgr
if [ -d $j ]
then
	echo $j is a directory.
	exit
elif [ ! -h $j ]
then
	if [ ! -f $j ]
	then
		/bin/ln -s /HORCM$j $j
	else
		echo $j is not a symbolic link.
		exit
	fi
fi

j=/etc/horcm.conf
if [ -d $j ]
then
	echo $j is a directory.
	exit
elif [ ! -h $j ]
then
	if [ ! -f $j ]
	then
		/bin/cp /HORCM$j $j
	fi
fi
