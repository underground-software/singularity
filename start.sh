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
./test.sh
podman-compose down -v
podman-compose up -d
podman-compose logs -f submatrix 2>&1 | sed '/Synapse now listening on TCP port 8008/ q'
./dev_sockets.sh &
./test-sub1.sh
podman-compose down -v
podman-compose up -d
./test-sub2.sh
podman-compose down -v
podman-compose up -d
./test-sub3.sh
