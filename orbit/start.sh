#!/bin/sh
uwsgi --plugin 'python,http' ./radius.ini
