#!/bin/sh
set -eux

cd "$(dirname "$0")"

# Restore all volumes from gzipped tar from stdin

# shellcheck disable=SC1091
. ./volumes_list

TMPDIR="$(mktemp -d)"

cd "${TMPDIR}"
tar -xz
for v in $VOLUMES; do
	podman volume rm "${v}"
	podman volume create "${v}"
	podman volume import "${v}" "${v}.tar"
done
cd "${OLDPWD}"

rm -r "${TMPDIR}"
