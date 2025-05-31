#!/bin/sh
#
# the warp drive allows you to enter hyperspace

set -e

PODMAN_COMPOSE=${PODMAN_COMPOSE:-podman-compose}

$PODMAN_COMPOSE exec orbit ./hyperspace.py "$@"
