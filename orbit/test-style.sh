#!/bin/bash

scan() { echo "[SCAN] ${1}" ; flake8 "${1}" || exit 1 ; }

scan radius.py
scan config.py
scan db2.py
scan hyperspace.py
