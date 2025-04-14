#!/bin/sh
set -ex

CONTAINER_NAME=$1
VOLUME_NAME=$2
DEST_DIR=$3
BUILD_PATH=$4
SRC_NAME=$5
EXC_NAME=$6
# Ensure the local coverage directory exists

# Execute commands inside the container to process gcov files
mkdir -p $DEST_DIR
CUR_DIR=$(pwd)
cd $DEST_DIR
rm -rf ./*
cd $CUR_DIR
podman exec -u 0 -it $CONTAINER_NAME /bin/bash -c '
    cd /coverage
    llvm-profdata merge -sparse *.profraw -o coverage.profdata
    mkdir -p cov
    mkdir -p '$BUILD_PATH'
    cp ./'$SRC_NAME' '$BUILD_PATH'/'$SRC_NAME'
    llvm-cov show /usr/local/bin/'$EXC_NAME' -instr-profile=coverage.profdata -format=html -output-dir=./cov
'
cp -r /var/lib/containers/storage/volumes/$VOLUME_NAME/_data/cov/* $DEST_DIR
chown 100:100 -R $DEST_DIR
chmod 777 -R $DEST_DIR