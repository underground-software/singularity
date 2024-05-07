#!/bin/sh
coverage run --data-file=/tmp/coverage --parallel-mode ./hyperspace.py "$@"
