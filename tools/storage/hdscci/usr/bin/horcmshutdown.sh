#!/bin/sh
#
# $Header: horcmshutdown.sh 1.00 07/04/1998 RM Copyright (c) 2000-2017, Hitachi, Ltd.
# $Header: horcmshutdown.sh 1.00 07/04/1998 RM Copyright (c) 2000-2017 Hewlett Packard Enterprise Development LP.
#
# Revision 1.2    31/07/03
#  changed for returning error value
#
# Revision 1.1    07/04/98
#  Initial revision

if [ $# -ne 0 ]
then
	for i do 
		HORCMINST=$i
		echo "inst $i:"
		export HORCMINST
		if [ -x /usr/bin/horcctl ]
		then
			/usr/bin/horcctl -S
		        if [ ! $? -eq 0 ]
			then
				echo "failed in shutting HORCM inst $i down"
				exit 1
			fi
		else
			echo "Not exist /usr/bin/horcctl"
			exit 1
		fi
	done
else
	if [ -x /usr/bin/horcctl ]
	then
		/usr/bin/horcctl -S
	        if [ ! $? -eq 0 ]
		then
			if [ "$HORCMINST" ]
			then
				echo "failed in shutting HORCM inst $HORCMINST down"
				exit 1
			else
				echo "failed in shutting HORCM down"
				exit 1
			fi
		fi
	else
	    echo "Not exist /usr/bin/horcctl"
	    exit 1
	fi
fi
exit 0


