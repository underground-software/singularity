#!/bin/sh
#
# the warp drive allows you to enter hyperspace

set -e

DOCKER_COMPOSE=${DOCKER_COMPOSE:-podman-compose}

$DOCKER_COMPOSE exec orbit ./hyperspace.py "$@"
