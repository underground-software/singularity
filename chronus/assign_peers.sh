#!/bin/sh

test -z "$1" && { echo "usage: $0 <assignment> "; exit 1; }

ASSIGNMENT=$1

python denis/who_submitted.py "${ASSIGNMENT}" | python denis/peers.py
