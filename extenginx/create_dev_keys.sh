#!/bin/sh
set -uexo pipefail

mkdir -p ssl
test -f ssl/ssl-dhparams.pem || openssl genpkey -genparam -algorithm DH -out ssl/ssl-dhparams.pem -pkeyopt dh_paramgen_prime_len:2048
test -f ssl/privkey.pem -a -f ssl/fullchain.pem || openssl req -x509 -newkey rsa:4096 -keyout ssl/privkey.pem -out ssl/fullchain.pem -sha256 -noenc -days 133337 -subj '/CN=localhost'
