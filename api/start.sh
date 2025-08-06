#!/bin/sh
uwsgi --master --plugin 'python,http' ./api.ini &
trap 'kill -INT $!' TERM
wait
