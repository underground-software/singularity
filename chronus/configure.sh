#!/bin/sh
set -e

COMPOSE=${COMPOSE:-podman-compose}

${COMPOSE} exec chronus ./configure.py "$@"

