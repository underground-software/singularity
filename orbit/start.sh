#!/bin/sh
memcached --daemon --unix-socket /run/orbit/memcached.sock
exec uwsgi --plugin 'python,http' ./radius.ini
