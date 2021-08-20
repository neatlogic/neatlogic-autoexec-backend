#!/bin/bash
SCRIPT=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT")
AUTOEXEC_HOME=$(dirname "$SCRIPT_DIR")

pip3 install virtualenv -t $AUTOEXEC_HOME/plib
pip3 install pymongo -t $AUTOEXEC_HOME/plib
pip3 install paramiko -t $AUTOEXEC_HOME/plib
pip3 install python-dateutil -t $AUTOEXEC_HOME/plib
pip3 install pyVim -t $AUTOEXEC_HOME/plib
pip3 install bigsuds -t $AUTOEXEC_HOME/plib
