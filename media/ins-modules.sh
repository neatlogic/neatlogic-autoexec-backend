#!/bin/bash
SCRIPT_DIR=$(dirname "$0")
AUTOEXEC_HOME="$SCRIPT_DIR/.."

pip3 install virtualenv -t $AUTOEXEC_HOME/plib
pip3 install pymongo -t $AUTOEXEC_HOME/plib
pip3 install paramiko -t $AUTOEXEC_HOME/plib
pip3 install python-dateutil -t $AUTOEXEC_HOME/plib
pip3 install pyVim -t $AUTOEXEC_HOME/plib
pip3 install bigsuds -t $AUTOEXEC_HOME/plib
pip3 install pyparsing -t $AUTOEXEC_HOME/plib
pip3 install ping3 -t $AUTOEXEC_HOME/plib
pip3 install requests -t $AUTOEXEC_HOME/plib
pip3 install pywbem -t $AUTOEXEC_HOME/plib
pip3 install pywbemtools -t $AUTOEXEC_HOME/plib
