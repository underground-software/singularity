#!/bin/sh
set -e
[ -z "$1" ] && { echo 'must pass path to .git dir of repo' >&2; exit 1; }
cd "$1" || { echo 'invalid repo' >&2; exit 1; }
touch git-daemon-export-ok
git config http.receivepack true
git update-server-info
