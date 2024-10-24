#!/bin/sh

set -e

DOCKER_COMPOSE=${DOCKER_COMPOSE:-podman-compose}

$DOCKER_COMPOSE exec denis ./update_tags.py "$@"
