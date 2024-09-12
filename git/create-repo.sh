#!/bin/sh
set -e
[ $# -ne 2 ] && { echo 'Usage: create-repo <name> <description>' >&2; exit 1; }

REPO="/var/lib/git/$1"

git init --bare "$REPO"
echo "$2" > "$REPO/description"
./setup-repo.sh "$REPO"
