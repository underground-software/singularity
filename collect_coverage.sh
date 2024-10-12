#!/bin/sh
set -ex

podman exec -i singularity_orbit_1 sh -exc '
cd /tmp
rm -rf .coverage htmlcov
coverage combine --keep coverage* >/dev/null 2>/dev/null
coverage html >/dev/null 2>/dev/null
tar -c htmlcov
' | tar -C coverage -x



CONTAINER_NAME="singularity_smtp_1"

# Ensure the local coverage directory exists
mkdir -p $LOCAL_COVERAGE_DIR

# Execute commands inside the container to process gcov files
podman exec -i $CONTAINER_NAME sh -exc '
    cd /smtp
    rm -rf default.profdata default.profraw htmlcov_smtp
    llvm-profdata merge -sparse default.profraw -o default.profdata
    llvm-cov show ./smtp -instr-profile=default.profdata -format=html -output-dir=htmlcov_coverage_smtp >/dev/null 2>&1
    tar -c htmlcov_coverage_smtp
' | tar -C coverage_smtp -x