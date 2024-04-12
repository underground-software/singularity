#!/bin/sh
set -eux

# Output gzipped tar of all volumes to stdout

. ./volumes_list

TMPDIR="$(mktemp -d)"

pushd "${TMPDIR}" > /dev/null
for v in $VOLUMES; do
	podman volume export "${v}" > "${v}.tar"
done
tar -cz .
popd > /dev/null

rm -r "${TMPDIR}"
