#!/usr/bin/env bash

# Testing script for singularity and orbit

# This line:
# - aborts the script after any pipeline returns nonzero (e)
# - shows all commands as they are run (x)
# - sets any dereference of an unset variable to trigger an error (u)
# - causes the return value of a pipeline to be the nonzero return value
#   of the furthest right failing command or zero if no command failed (o pipefail)
set -exuo pipefail

DOCKER=${DOCKER:-podman}
DOCKER_COMPOSE=${DOCKER_COMPOSE:-podman-compose}

require() { command -v "$1" > /dev/null || { echo "error: $1 command required yet absent" ; exit 1 ; } ; }
require curl
require jq
require flake8
require "${DOCKER}"
require "${DOCKER_COMPOSE}"

# Check for shell script style compliance with shellcheck
./script-lint.sh

# Check python style compliance
flake8

# Create test dir if it does not exist yet
mkdir -p test

# Reset the test directory
rm -f test/*

HOSTNAME_FROM_DOTENV="$(env -i sh -c '
set -o allexport
. ./.env
exec jq -r -n "env.SINGULARITY_HOSTNAME"
')"

SINGULARITY_HOSTNAME=${SINGULARITY_HOSTNAME:-"${HOSTNAME_FROM_DOTENV}"}

${DOCKER} cp singularity_nginx_1:/etc/ssl/nginx/fullchain.pem test/ca_cert.pem

CURL_OPTS=( \
--verbose \
--cacert test/ca_cert.pem \
--fail \
--no-progress-meter \
)

# Check that registration fails before user creation
curl --url "https://$SINGULARITY_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "student_id=1234" \
  | tee test/register_fail_no_user \
  | grep "msg = no such student"

# Check that login fails before user creation
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "username=user&password=pass" \
  | tee test/login_fail_no_user \
  | grep "msg = authentication failure"

# Check that we can create a user
orbit/warpdrive.sh -u user -i 1234 -n

# Check that registration fails with incorrect student id
curl --url "https://$SINGULARITY_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "student_id=123" \
  | tee test/register_fail_wrong \
  | grep "msg = no such student"

# Check that registration succeeds with correct student id
curl --url "https://$SINGULARITY_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "student_id=1234" \
  | tee test/register_success \
  | grep "msg = welcome to the classroom"

REGISTER_PASS="$(sed -nr 's/.*Password: ([^<]*).*/\1/p' < test/register_success | tr -d '\n')"

# Check that registration fails when student id is used for a second time
curl --url "https://$SINGULARITY_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "student_id=1234" \
  | tee test/register_fail_duplicate \
  | grep "msg = no such student"

# Check that login fails when credentials are invalid
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "username=user&password=invalid" \
  | tee test/login_fail_invalid \
  | grep "msg = authentication failure"

# Check that login succeeds when credentials are valid
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "username=user&password=${REGISTER_PASS}" \
  | tee test/login_success \
  | grep "msg = user authenticated by password"

# Check that the user can get the empty list of email on the server
curl --url "pop3s://$SINGULARITY_HOSTNAME" \
  --unix-socket ./socks/pop3s.sock \
  "${CURL_OPTS[@]}" \
  --user "user:${REGISTER_PASS}" \
  | tee test/pop_get_empty \
  | diff <(printf '\r\n') /dev/stdin

CR=$(printf "\r")
# Check that the user can send a message to the server
(
curl --url "smtps://$SINGULARITY_HOSTNAME" \
  --unix-socket ./socks/smtps.sock \
  "${CURL_OPTS[@]}" \
  --mail-from "user@$SINGULARITY_HOSTNAME" \
  --mail-rcpt "other@$SINGULARITY_HOSTNAME" \
  --upload-file - \
  --user "user:${REGISTER_PASS}" <<EOF
Subject: Message Subject$CR
$CR
To whom it may concern,$CR
$CR
Bottom text$CR
EOF
) | tee test/smtp_send_email \
  | diff <(printf "") /dev/stdin


# Verify that no email shows up without the journal being updated
curl --url "pop3s://$SINGULARITY_HOSTNAME" \
  --unix-socket ./socks/pop3s.sock \
  "${CURL_OPTS[@]}" \
  --user "user:${REGISTER_PASS}" \
  | tee test/pop_get_empty_no_update \
  | diff <(printf '\r\n') /dev/stdin

# create a user that will have limited access to the inbox
orbit/warpdrive.sh -u resu -p ssap -n

# Limit `resu`'s access to the empty inbox
${DOCKER_COMPOSE} exec pop /usr/local/bin/restrict_access /var/lib/email/journal/journal -d resu

# Update list of email to include new message
${DOCKER_COMPOSE} exec pop /usr/local/bin/init_journal /var/lib/email/journal/journal /var/lib/email/journal/temp /var/lib/email/mail

# Check that the user can get the most recent message sent to the server
curl --url "pop3s://$SINGULARITY_HOSTNAME/1" \
  --unix-socket ./socks/pop3s.sock \
  "${CURL_OPTS[@]}" \
  --user "user:${REGISTER_PASS}" \
  | tee test/pop_get_message \
  | grep "Bottom text"

# Verify that no email shows up for `resu`
curl --url "pop3s://$SINGULARITY_HOSTNAME" \
  --unix-socket ./socks/pop3s.sock \
  "${CURL_OPTS[@]}" \
  --user "resu:ssap" \
  | tee test/pop_get_empty_restricted \
  | diff <(printf '\r\n') /dev/stdin


# Remove limit on `resu`'s access to the inbox
${DOCKER_COMPOSE} exec pop /usr/local/bin/restrict_access /var/lib/email/journal/journal -a resu

# Check that `resu` can now get the most recent message sent to the server
curl --url "pop3s://$SINGULARITY_HOSTNAME/1" \
  --unix-socket ./socks/pop3s.sock \
  "${CURL_OPTS[@]}" \
  --user "resu:ssap" \
  | tee test/pop_unrestricted_get_message \
  | grep "Bottom text"

# If you get a 429 error from one of the matrix tests, restart the server and try again
# Synapse has rate-limiting behavior for login requests indicated by this 429 HTTP code

# Check that the user can login to matrix with their orbit ID
curl --url "https://$SINGULARITY_HOSTNAME/_matrix/client/r0/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --header "Content-Type: application/json" \
  --data "{
        \"type\": \"m.login.password\",
        \"user\": \"@user:$SINGULARITY_HOSTNAME\",
        \"password\": \"${REGISTER_PASS}\"
      }" \
  | tee test/matrix_login_success \
  | grep "access_token"

# Check that the user cannot login to matrix with an invalid orbit ID
curl --url "https://$SINGULARITY_HOSTNAME/_matrix/client/r0/login" \
  --unix-socket ./socks/https.sock \
  --verbose \
  --cacert test/ca_cert.pem \
  --no-progress-meter \
  --header "Content-Type: application/json" \
  --data "{
        \"type\": \"m.login.password\",
        \"user\": \"@user:$SINGULARITY_HOSTNAME\",
        \"password\": \"ssap\"
      }" \
  | tee test/matrix_login_invalid \
  | grep '{"errcode":"M_FORBIDDEN","error":"Invalid username or password"}'

echo "ALL TESTS PASS"
