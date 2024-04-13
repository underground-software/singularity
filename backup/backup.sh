#!/bin/sh
set -eux

cd "$(dirname "$0")"

# Output gzipped tar of all volumes to stdout

# shellcheck disable=SC1091
. ./volumes_list

TMPDIR="$(mktemp -d)"

cd "${TMPDIR}"
for v in $VOLUMES; do
	podman volume export "${v}" > "${v}.tar"
done
tar -cz .
cd "${OLDPWD}"

rm -r "${TMPDIR}"
