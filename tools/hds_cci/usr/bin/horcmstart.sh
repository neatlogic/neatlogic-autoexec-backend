#!/bin/sh
#
# $Header: horcmstart.sh 1.00 07/04/1998 RM Copyright (c) 2000-2017, Hitachi, Ltd.
# $Header: horcmstart.sh 1.00 07/04/1998 RM Copyright (c) 2000-2017 Hewlett Packard Enterprise Development LP.
#
# Revision 1.2    27/10/05
#  HORCMSTART_WAIT has been available as timeout value when horcmgr starts.
# Revision 1.1    07/04/98
#  Initial revision

cd /

if [ "$HORCMSTART_WAIT" ]
then
	let wait=$HORCMSTART_WAIT/5
	if [ $wait -lt 1 ]
	then
		wait=
	fi
fi

if [ $# -ne 0 ]
then
	for i do 
		HORCM_CONF=/etc/horcm$i.conf
		HORCM_LOG=/HORCM/log$i/curlog
		HORCM_LOGS=/HORCM/log$i/tmplog
		HORCMINST=$i
		export HORCMINST
		export HORCM_LOG
		export HORCM_LOGS
		export HORCM_CONF
		if [ -x /etc/horcmgr ]
		then
			/etc/horcmgr -check
			tmp=$?
			if [ $tmp -eq 1 ]
			then
		                echo "HORCM inst $i has already been running."
				exit $tmp
			fi
			if [ -w $HORCM_LOG -a -d $HORCM_LOG ]
			then
			        if [ -w $HORCM_LOGS -a -d $HORCM_LOGS ]
			        then
			                /bin/rm -rf $HORCM_LOGS
				else
					/bin/mkdir -p $HORCM_LOGS
			                /bin/rm -rf $HORCM_LOGS
			        fi
				/bin/mv $HORCM_LOG  $HORCM_LOGS
			fi
	                echo "starting HORCM inst $i"
			/etc/horcmgr $wait
			tmp=$?
		        if [ $tmp -eq 0 ]
		        then
		                echo "HORCM inst $i starts successfully."
		        elif [ $tmp -eq 1 ]
			then
		                echo "HORCM inst $i has already been running."
				exit $tmp
		        elif [ $tmp -eq 2 ]
			then
		                echo "HORCM inst $i is not able to create any child-processes."
				exit $tmp
		        elif [ $tmp -eq 3 ]
			then
		                echo "HORCM inst $i has failed to start."
				exit $tmp
		        elif [ $tmp -eq 4 ]
			then
		                echo "HORCM inst $i finished successfully."
				exit 0
		        elif [ $tmp -eq 5 ]
			then
		                echo "HORCM inst $i has catched a signal."
				exit $tmp
		        else
		                echo "/etc/horcmgr has catched a signal."
				exit $tmp
			fi
		fi
	done
	exit $tmp
elif [ ! "$HORCMINST" ]
then
	if [ ! "$HORCM_CONF" ]
	then
		HORCM_CONF=/etc/horcm.conf
	fi
	if [ ! "$HORCM_LOG" ]
	then
		HORCM_LOG=/HORCM/log/curlog
	fi
	if [ ! "$HORCM_LOGS" ]
	then
		HORCM_LOGS=/HORCM/log/tmplog
	fi

	export HORCM_CONF
	export HORCM_LOG
	export HORCM_LOGS
	if [ -x /etc/horcmgr ]
	then
		/etc/horcmgr -check
		tmp=$?
		if [ $tmp -eq 1 ]
		then
	                echo "HORCM has already been running."
			exit $tmp
		fi
		if [ -w $HORCM_LOG -a -d $HORCM_LOG ]
		then
		        if [ -w $HORCM_LOGS -a -d $HORCM_LOGS ]
		        then
		                /bin/rm -rf $HORCM_LOGS
			else
				/bin/mkdir -p $HORCM_LOGS
		                /bin/rm -rf $HORCM_LOGS
		        fi
			/bin/mv $HORCM_LOG  $HORCM_LOGS
		fi
		echo "starting HORCM"
		/etc/horcmgr $wait
		tmp=$?
	        if [ $tmp -eq 0 ]
	        then
	                echo "HORCM starts successfully."
	        elif [ $tmp -eq 1 ]
		then
	                echo "HORCM has already been running."
	        elif [ $tmp -eq 2 ]
		then
	                echo "HORCM is not able to create any child-processes."
	        elif [ $tmp -eq 3 ]
		then
	                echo "HORCM has failed to start."
	        elif [ $tmp -eq 4 ]
		then
	                echo "HORCM finished successfully."
			exit 0
	        elif [ $tmp -eq 5 ]
		then
	                echo "HORCM daemon has catched a signal."
	        else
	                echo "/etc/horcmgr has catched a signal."
	        fi
	fi
	exit $tmp
else
	i=$HORCMINST
	if [ ! "$HORCM_CONF" ]
	then
		HORCM_CONF=/etc/horcm$i.conf
	fi
	if [ ! "$HORCM_LOG" ]
	then
		HORCM_LOG=/HORCM/log$i/curlog
	fi
	if [ ! "$HORCM_LOGS" ]
	then
		HORCM_LOGS=/HORCM/log$i/tmplog
	fi
	export HORCM_LOG
	export HORCM_LOGS
	export HORCM_CONF
	if [ -x /etc/horcmgr ]
	then
		/etc/horcmgr -check
		tmp=$?
		if [ $tmp -eq 1 ]
		then
	                echo "HORCM inst $i has already been running."
			exit $tmp
		fi
		if [ -w $HORCM_LOG -a -d $HORCM_LOG ]
		then
		        if [ -w $HORCM_LOGS -a -d $HORCM_LOGS ]
		        then
		                /bin/rm -rf $HORCM_LOGS
			else
				/bin/mkdir -p $HORCM_LOGS
		                /bin/rm -rf $HORCM_LOGS
		        fi
			/bin/mv $HORCM_LOG  $HORCM_LOGS
		fi
                echo "starting HORCM inst $i"
		/etc/horcmgr $wait
		tmp=$?
	        if [ $tmp -eq 0 ]
	        then
	                echo "HORCM inst $i starts successfully."
	        elif [ $tmp -eq 1 ]
		then
	                echo "HORCM inst $i has already been running."
	        elif [ $tmp -eq 2 ]
		then
	                echo "HORCM inst $i is not able to create any child-processes."
	        elif [ $tmp -eq 3 ]
		then
	                echo "HORCM inst $i has failed to start."
	        elif [ $tmp -eq 4 ]
		then
	                echo "HORCM inst $i finished successfully."
			exit 0
	        elif [ $tmp -eq 5 ]
		then
	                echo "HORCM inst $i has catched a signal."
	        else
	                echo "/etc/horcmgr has catched a signal."
		fi
	fi
	exit $tmp
fi


