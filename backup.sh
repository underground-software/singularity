#!/bin/sh

# Output gzipped tar of all volumes to stdout

VOLUMES='
singularity_email
singularity_orbit-db
singularity_ssl-certs
singularity_submatrix-data
'

pushd "$(mktemp -d)" > /dev/null
for v in $VOLUMES; do
	podman volume export ${v} > ${v}.tar
done
tar -cz .
popd > /dev/null
