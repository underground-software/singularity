#!/bin/sh

# Restore all volumes from gzipped tar from stdin

VOLUMES='
singularity_email
singularity_orbit-db
singularity_ssl-certs
singularity_submatrix-data
'

pushd "$(mktemp -d)" > /dev/null
tar -xz
for v in $VOLUMES; do
	podman volume rm ${v}
	podman volume create ${v}
	podman volume import ${v} ${v}.tar
done
popd > /dev/null
