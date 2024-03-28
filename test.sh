#!/usr/bin/env bash

# Testing script for singularity and orbit

# This line:
# - aborts the script after any pipeline returns nonzero (e)
# - shows all commands as they are run (x)
# - sets any dereference of an unset variable to trigger an error (u)
# - causes the return value of a pipeline to be the nonzero return value
#   of the furthest right failing command or zero if no command failed (o pipefail)
set -exuo pipefail

# This function will push an action to a stack of items to be done on script exit
# in the reverse order that they are passed to this function
trap ":" EXIT
cleanup_add() {
	trap -- "$(
		printf '%s\n' "$1"
		# get stack is invoked in eval but shellcheck cannot tell since it is indirect
		# shellcheck disable=SC2317
		get_stack() { printf '%s\n' "$3"; }
		eval "get_stack $(trap -p EXIT)"
	)" EXIT
}

# Deliver a bomb.exe to the inbox
nuke_mail() {
	podman run --rm -v singularity_email:/mnt alpine:3.19 sh -c 'rm -f /mnt/mail/* /mnt/logs/*'
}

require() { command -v "$1" || { echo "error: $1 command required yet absent" ; exit 1 ; } ; }
require curl
require flake8
require podman
require shellcheck

# Reset the test directory
mkdir -p test
rm -f test/*

podman volume export singularity_email > test/email_orig.tar

cleanup_add "podman volume import singularity_email test/email_orig.tar"

nuke_mail

# Import empty email volume for testing
xxd -r <<-'EOF' | gunzip | podman volume import singularity_email -
00000000: 1f8b 0800 0000 0000 0003 cbc9 4f2f d667  ............O/.g
00000010: a02d 3000 0273 5353 300d 04e8 3498 6d68  .-0..sSS0...4.mh
00000020: 6266 6068 6868 6c60 6acc 6060 6860 6460  bf`hhhl`j.``h`d`
00000030: c4a0 604a 6377 8141 6971 4962 11d0 2994  ..`Jcw.AiqIb..).
00000040: 9a83 eeb9 2102 7213 3373 0661 fc1b 9a19  ....!.r.3s.a....
00000050: 8cc6 ff28 1805 a360 14d0 1200 00a5 4bb9  ...(...`......K.
00000060: 5f00 0800 00                             _....
EOF

cleanup_add nuke_mail

# TODO: login returns 401 so we don't set --fail on the curl command

DEVEL=${DEVEL:-""}
STAGING=${STAGING:-""}
EMAIL_HOSTNAME="kdlp.underground.software"

# NOTE: don't set DEVEL and STAGING at the same time

if [ -n "$DEVEL" ]; then
	EMAIL_HOSTNAME="localhost"
fi

if [ -n "$STAGING" ]; then
	EMAIL_HOSTNAME="dev.underground.software"
fi

# Check that registration fails before user creation
curl --url "https://$EMAIL_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "student_id=1234" \
  | tee test/register_fail_no_user \
  | grep "msg = no such student"

# Check that login fails before user creation
curl --url "https://$EMAIL_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  --verbose \
  --insecure \
  --no-progress-meter \
  --data "username=user&password=pass" \
  | tee test/login_fail_no_user \
  | grep "msg = authentication failure"

# Check that we can create a user
orbit/warpdrive.sh \
  -u user -p pass -i 1234 -n \
  | tee test/create_user \
  | grep "credentials(username: user, password:pass)"

cleanup_add "orbit/warpdrive.sh \
  -u user -w \
  | tee test/delete_user \
  | grep 'user'"

# Check that registration fails with incorrect student id
curl --url "https://$EMAIL_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "student_id=123" \
  | tee test/register_fail_wrong \
  | grep "msg = no such student"

# Check that registration succeeds with correct student id
curl --url "https://$EMAIL_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "student_id=1234" \
  | tee test/register_success \
  | grep "msg = welcome to the classroom"

# Check that registration fails when student id is used for a second time
curl --url "https://$EMAIL_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "student_id=1234" \
  | tee test/register_fail_duplicate \
  | grep "msg = no such student"

# Check that login fails when credentials are invalid
curl --url "https://$EMAIL_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  --verbose \
  --insecure \
  --no-progress-meter \
  --data "username=user&password=invalid" \
  | tee test/login_fail_invalid \
  | grep "msg = authentication failure"

# Check that login succeeds when credentials are valid
curl --url "https://$EMAIL_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "username=user&password=pass" \
  | tee test/login_success \
  | grep "msg = user authenticated by password"

# Check that the user can get the empty list of email on the server
curl --url "pop3s://$EMAIL_HOSTNAME" \
  --unix-socket ./socks/pop3s.sock \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --user user:pass \
  | tee test/pop_get_empty \
  | diff <(printf '\r\n') /dev/stdin

CR=$(printf "\r")
# Check that the user can send a message to the server
(
curl --url "smtps://$EMAIL_HOSTNAME" \
  --unix-socket ./socks/smtps.sock \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --mail-from "user@$EMAIL_HOSTNAME" \
  --mail-rcpt "other@$EMAIL_HOSTNAME" \
  --upload-file - \
  --user 'user:pass' <<EOF
Subject: Message Subject$CR
$CR
To whom it may concern,$CR
$CR
Bottom text$CR
EOF
) | tee test/smtp_send_email \
  | diff <(printf "") /dev/stdin
  
# Check that the user can get the most recent message sent to the server
curl --url "pop3s://$EMAIL_HOSTNAME/1" \
  --unix-socket ./socks/pop3s.sock \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --user user:pass \
  | tee test/pop_get_message \
  | grep "Bottom text"

# Check for shell script styyle compliance with shellcheck
shellcheck test.sh
shellcheck orbit/test-style.sh

# Check python style compliance with flake8
pushd orbit
cleanup_add popd
./test-style.sh
