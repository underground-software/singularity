#!/bin/sh

set -ex

mkdir -p /var/lib/containers/storage
mount -t tmpfs tmpfs /var/lib/containers/storage
podman-compose build
podman-compose up -d
# wait until synapse is done initializing
podman-compose logs -f submatrix 2>&1 | sed '/Synapse now listening on TCP port 8008/ q'
if [ -f test.sh ]
then
	./test.sh
	if [ -f test-sub.sh ]
	then
		podman-compose down
		yes | podman volume prune
		podman-compose up -d
		podman-compose logs -f submatrix 2>&1 | sed '/Synapse now listening on TCP port 8008/ q'
		./dev_sockets.sh &
		git config --global user.name PINP
		git config --global user.email podman@podman
		./test-sub.sh
		./test-sub-check.sh
		podman-compose down
		yes | podman volume prune
		podman-compose up -d
		./test-sub2.sh
		podman-compose down
		yes | podman volume prune
		podman-compose up -d
		./test-sub3.sh

	fi
else
	virtualenv .
	pip install -r requirements.txt
	pytest
fi
podman-compose down
