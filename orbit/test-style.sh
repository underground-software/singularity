#!/bin/bash

FLAKE8_FLAGS=""

while getopts "v" FLAG; do
        case $FLAG in
        v)
                FLAKE8_FLAGS="$FLAKE8_FLAGS "
                ;;
        esac
done

SOURCES=""
scan() {
	echo "[SCAN] ${1}"
        flake8 ${FLAKE8_FLAGS} ${1}
        RES=$?
        if test "$RES" -ne "0"
        then
                exit 1
        fi
}

scan radius.py
scan config.py
scan db.py
scan hyperspace.py
