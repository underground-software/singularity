#!/bin/sh
set -ex

./collect_coverage.sh singularity_smtp_1 singularity_smtp_coverage ./smtp_coverage/ /smtp smtp.c smtp_
./collect_coverage.sh singularity_pop_1 singularity_pop_coverage ./pop_coverage/ /pop pop3.c pop3_
