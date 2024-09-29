#!/bin/sh
set -e

COMPOSE=${COMPOSE:-podman-compose}

${COMPOSE} exec mailman ./inspector.py "$@"

