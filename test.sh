#!/usr/bin/env bash

# Testing script for singularity and orbit

# This line:
# - aborts the script after any pipeline returns nonzero (e)
# - shows all commands as they are run (x)
# - sets any dereference of an unset variable to trigger an error (u)
# - causes the return value of a pipeline to be the nonzero return value
#   of the furthest right failing command or zero if no command failed (o pipefail)
set -exuo pipefail

require() { command -v "$1" > /dev/null || { echo "error: $1 command required yet absent" ; exit 1 ; } ; }
require curl
require flake8
require chcon

# Check for shell script style compliance with shellcheck
./script-lint.sh

# Check python style compliance with flake8
pushd orbit
./test-style.sh
popd

# Reset the tests and mail directories
sudo rm -rf test email/logs/* email/mail/*
mkdir -p test

# This is a temporary workaround until we properly implement volumes
chcon -R -t container_file_t email

# TODO: login returns 401 so we don't set --fail on the curl command

DEVEL=${DEVEL:-""}
STAGING=${STAGING:-""}
PORT=${PORT:-443}
POP_PORT=${POP_PORT:-995}
SMTP_PORT=${SMTP_PORT:-465}
EMAIL_HOSTNAME="kdlp.underground.software"

# NOTE: don't set DEVEL and STAGING at the same time

if [ -n "$DEVEL" ]; then
	PORT=1443
	POP_PORT=1995
	SMTP_PORT=1465
	EMAIL_HOSTNAME="localhost"
fi

if [ -n "$STAGING" ]; then
	EMAIL_HOSTNAME="dev.underground.software"
fi

# Check that registration fails before user creation
curl --url "https://localhost:$PORT/register" \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "student_id=1234" \
  | tee test/register_fail_no_user \
  | grep "msg = no such student"

# Check that login fails before user creation
curl --url "https://localhost:$PORT/login" \
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

# Check that registration fails with incorrect student id
curl --url "https://localhost:$PORT/register" \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "student_id=123" \
  | tee test/register_fail_wrong \
  | grep "msg = no such student"

# Check that registration succeeds with correct student id
curl --url "https://localhost:$PORT/register" \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "student_id=1234" \
  | tee test/register_success \
  | grep "msg = welcome to the classroom"

# Check that registration fails when student id is used for a second time
curl --url "https://localhost:$PORT/register" \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "student_id=1234" \
  | tee test/register_fail_duplicate \
  | grep "msg = no such student"

# Check that login fails when credentials are invalid
curl --url "https://localhost:$PORT/login" \
  --verbose \
  --insecure \
  --no-progress-meter \
  --data "username=user&password=invalid" \
  | tee test/login_fail_invalid \
  | grep "msg = authentication failure"

# Check that login succeeds when credentials are valid
curl --url "https://localhost:$PORT/login" \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --data "username=user&password=pass" \
  | tee test/login_success \
  | grep "msg = user authenticated by password"

# Check that the user can get the empty list of email on the server
curl --url "pop3s://localhost:$POP_PORT" \
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
curl --url "smtps://localhost:$SMTP_PORT" \
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
curl --url "pop3s://localhost:$POP_PORT/1" \
  --verbose \
  --insecure \
  --fail \
  --no-progress-meter \
  --user user:pass \
  | tee test/pop_get_message \
  | grep "Bottom text"

# Check that we can delete a user
orbit/warpdrive.sh \
  -u user -w \
  | tee test/delete_user \
  | grep "user"
