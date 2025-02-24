#!/bin/sh
memcached --daemon --unix-socket /run/orbit/memcached.sock
uwsgi --master --plugin 'python,http' ./radius.ini &
trap 'kill -INT $!' TERM
wait
