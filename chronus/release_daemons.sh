#!/bin/sh

# let the daemons loose

_exit() {
	exit 0
}

trap _exit SIGTERM

run-at "$(echo "$(date +%s) + 5" | bc)" "./assign_peers.sh" "exercise0" > 5secs.peers &

run-at "$(echo "$(date +%s) + 15" | bc)" "./assign_peers.sh" "exercise0" > 15secs.peers &

sleep 100 &

wait
