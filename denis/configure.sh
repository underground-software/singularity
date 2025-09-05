#!/bin/sh
set -e

PODMAN=${PODMAN:-podman}
COMPOSE=${COMPOSE:-podman-compose}

# a rubric is passed as a path to a file,
# but the main script is executed inside the container
# so copy any rubric into the container,
# if one is specified.
get_next=
rubric_file=
for arg in "$@"
do
	if [ "$arg" = '-r' ]
	then
		get_next=yes
	elif [ -n "$get_next" ]
	then
		rubric_file=$arg
	fi
done

if [ -n "$rubric_file" ]
then
	${PODMAN} cp "$rubric_file" singularity_denis_1:/tmp/rubric
fi


${COMPOSE} exec denis ./configure.py "$@"

