#!/bin/sh
set -e

COMPOSE=${COMPOSE:-podman-compose}

${COMPOSE} exec denis ./configure.py "$@"

