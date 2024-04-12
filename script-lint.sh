#!/bin/sh

require() { command -v "$1" > /dev/null || { echo "error: $1 command required yet absent" ; exit 1 ; } ; }
require shellcheck

set -ex

shellcheck script-lint.sh
shellcheck test.sh
shellcheck orbit/test-style.sh
shellcheck orbit/warpdrive.sh

# -x needed to make shellcheck follow `source` command
shellcheck -x backup/backup.sh
shellcheck -x backup/restore.sh
