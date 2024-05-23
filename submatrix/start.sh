#!/bin/sh
export PYTHONPATH="/usr/local/share/submatrix:${PYTHONPATH}"
exec synapse_homeserver -c /etc/synapse/homeserver.yaml
