#!/bin/sh
set -e

PODMAN_COMPOSE=${PODMAN_COMPOSE:-podman-compose}

$PODMAN_COMPOSE exec git ./create-repo.sh "$@"
