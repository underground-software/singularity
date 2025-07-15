#!/bin/sh

set -ex

mkdir -p \
	repos \
	docs \
	;

ln -s .git gitdir

podman-compose build
podman-compose up -d
trap 'podman-compose down -v' EXIT

# wait until synapse is done initializing
podman-compose logs -f submatrix 2>&1 | sed '/Synapse now listening on TCP port 8008/ q'
if [ -f test.sh ]
then
	./test.sh
else
	virtualenv .
	pip install -r requirements.txt
	pytest
fi
