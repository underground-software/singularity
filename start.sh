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
	if [ -f test-sub.sh ]
	then
		podman-compose down -v
		podman-compose up -d
		podman-compose logs -f submatrix 2>&1 | sed '/Synapse now listening on TCP port 8008/ q'
		./dev_sockets.sh &
		git config --global user.name PINP
		git config --global user.email podman@podman
		./test-sub.sh
		./test-sub-check.sh
		podman-compose down -v
		podman-compose up -d
		./test-sub2.sh
		podman-compose down -v
		podman-compose up -d
		./test-sub3.sh
		podman-compose down -v
		podman-compose up -d
		./test-sub4.sh

	fi
else
	virtualenv .
	pip install -r requirements.txt
	pytest
fi
