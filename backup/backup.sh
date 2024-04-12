#!/bin/sh
set -eux

# Output gzipped tar of all volumes to stdout

. ./volumes_list

TMPDIR="$(mktemp -d)"

cd "${TMPDIR}"
for v in $VOLUMES; do
	podman volume export "${v}" > "${v}.tar"
done
tar -cz .
cd "${OLDPWD}"

rm -r "${TMPDIR}"
