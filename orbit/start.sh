#!/bin/sh
memcached --daemon --unix-socket /run/orbit/memcached.sock
uwsgi --plugin 'python,http' ./radius.ini
