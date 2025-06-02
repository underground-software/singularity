#!/bin/sh

require() { command -v "$1" > /dev/null || { echo "error: $1 command required yet absent" ; exit 1 ; } ; }
require shellcheck

set -ex

# -x needed to make shellcheck follow `source` command
shellcheck script-lint.sh
shellcheck -x test.sh
shellcheck -x test-sub.sh
shellcheck -x test-sub-check.sh
shellcheck -x test-sub2.sh
shellcheck orbit/warpdrive.sh
shellcheck denis/configure.sh
shellcheck mailman/inspector.sh
shellcheck git/admin.sh
shellcheck git/create-repo.sh
shellcheck git/setup-repo.sh
shellcheck git/cgi-bin/git-receive-pack
shellcheck git/hooks/post-update

shellcheck -x backup/backup.sh
shellcheck -x backup/restore.sh
