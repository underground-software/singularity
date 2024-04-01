#!/bin/sh

require() { command -v "$1" > /dev/null || { echo "error: $1 command required yet absent" ; exit 1 ; } ; }
require flake8

set -ex

flake8 radius.py
flake8 config.py
flake8 db.py
flake8 hyperspace.py
