#!/bin/sh

# Output gzipped tar of all volumes to stdout

. ./volumes_list

pushd "$(mktemp -d)" > /dev/null
for v in $VOLUMES; do
	podman volume export ${v} > ${v}.tar
done
tar -cz .
popd > /dev/null
