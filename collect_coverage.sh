#!/bin/sh
set -ex

podman exec -i singularity_orbit_1 sh -exc '
cd /tmp
rm -rf .coverage htmlcov
coverage combine --keep coverage* >/dev/null 2>/dev/null
coverage html >/dev/null 2>/dev/null
tar -c htmlcov
' | tar -C coverage -x
