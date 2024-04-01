#!/bin/bash


set -ex

flake8 radius.py
flake8 config.py
flake8 db.py
flake8 hyperspace.py
