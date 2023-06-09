#!/bin/bash
PROG_PATH=${BASH_SOURCE[0]}
echo $PROG_PATH
AUTOEXEC_DIR=$(cd $(dirname "$PROG_PATH")/.. && pwd)

if [[ -e "/tmp/autoexec.tgz" ]]; then
    rm -f "/tmp/autoexec.tgz"
fi

#cd "$AUTOEXEC_DIR" && tar -cvzf /tmp/autoexec.update.tgz --exclude .DS_Store --exclude __pycache__ --exclude plugins/local/pllib bin discovery i18n lib media plugins

cd "$AUTOEXEC_DIR" && tar -cvzf /tmp/autoexec.update.tgz --exclude .DS_Store --exclude __pycache__ --exclude plugins/local/pllib --exclude plugins/local/media bin lib i18n plugins
