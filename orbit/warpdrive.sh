#!/bin/sh -e
#
# the warp drive allows you to enter hyperspace

require() { command -v "$1" > /dev/null || { echo "error: $1 command required yet absent" ; exit 1 ; } ; }

cd "$(dirname "$0")"

DOCKER=${DOCKER:-podman}

require "${DOCKER}"

CONTAINER=${CONTAINER:-singularity_orbit_1}

$DOCKER exec -i "$CONTAINER" ./hyperspace.py "$@"
