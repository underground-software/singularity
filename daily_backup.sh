#!/usr/bin/env bash

# Run this in the singularity repo

while true; do
	./backup/backup.sh > "/var/backup/$(date +%s).tar.gz"
	sleep 1d
done
