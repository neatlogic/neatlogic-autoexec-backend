#!/bin/bash
SCRIPT_DIR=$(pwd)
echo "SCRIPT_DIR:$SCRIPT_DIR"
if [ ! -d "$SCRIPT_DIR/uemcli" ] ; then
   mkdir -p "$SCRIPT_DIR/uemcli"
fi
rpm -i –prefix="$SCRIPT_DIR/uemcli" NaviCLI-Linux-64-x86-en_US-7.33.9.1.84-1.x86_64.rpm 
