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

require() { command -v "$1" > /dev/null || { echo "error: $1 command required yet absent" ; exit 1 ; } ; }
require curl
require jq
require flake8
require "${DOCKER}"

# Check for shell script style compliance with shellcheck
./script-lint.sh

# Check python style compliance with flake8
pushd orbit
./test-style.sh
popd

flake8 submatrix/orbit_auth.py

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

# Check basic markdown functionality
curl --url "https://$SINGULARITY_HOSTNAME/index.md" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  | tee test/markdown_index \
  | grep '<h3>TL;DR:</h3>'

# Check invalid markdown page
curl --url "https://$SINGULARITY_HOSTNAME/not_real_index.md" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --no-fail \
  | tee test/markdown_nonexistant \
  | grep '<h1>HTTP ERROR 404: NOT FOUND</h1>'

# Check innapropriate method
curl --url "https://$SINGULARITY_HOSTNAME/index.md" \
  --unix-socket ./socks/https.sock \
  --request DELETE \
  "${CURL_OPTS[@]}" \
  --no-fail \
  | tee test/method_innapropriate \
  | grep '<h1>HTTP ERROR 405: METHOD NOT ALLOWED</h1>'

# Check post to get only path
curl --url "https://$SINGULARITY_HOSTNAME/index.md" \
  --unix-socket ./socks/https.sock \
  --data "foo=bar" \
  "${CURL_OPTS[@]}" \
  --no-fail \
  | tee test/method_post_to_get_only \
  | grep '<h1>HTTP ERROR 405: METHOD NOT ALLOWED</h1>'

# Check that list of users (roster) is empty
orbit/warpdrive.sh -r \
  | tee test/roster_empty \
  | diff /dev/stdin <(echo "Users:")

# Check that registration form can be accessed
curl --url "https://$SINGULARITY_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  | tee test/register_fail_no_user \
  | grep "Student ID:"

# Check that submitting form without student id fails
curl --url "https://$SINGULARITY_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  --data \
  "${CURL_OPTS[@]}" \
  | tee test/register_fail_no_user \
  | grep "msg = you must provide a student id"


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

# Check that list of users has new user
orbit/warpdrive.sh -r \
  | tee test/roster_after_creation \
  | diff /dev/stdin <(printf "Users:\nuser, None, 1234\n")

# Check that login fails after user creation but before registration
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "username=user&password=pass" \
  | tee test/login_fail_no_reg \
  | grep "msg = authentication failure"

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

# Check that list of users has updated password hash
# (bcrypt hash will contain a $, but obviously `None` will not)
orbit/warpdrive.sh -r \
  | tee test/roster_after_registration \
  | grep "user, .*\$.*, 1234"

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

# Check that list of sessions is empty
orbit/warpdrive.sh -l \
  | tee test/sessions_empty \
  | diff /dev/stdin <(echo "Sessions:")

# Check that login succeeds when credentials are valid
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie-jar test/login_cookies \
  --data "username=user&password=${REGISTER_PASS}" \
  | tee test/login_success \
  | grep "msg = user authenticated by password"

# Check that list of sessions contains new session
orbit/warpdrive.sh -l \
  | tee test/sessions_logged_in \
  | grep "user"

# Check that login page recognizes cookie
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie test/login_cookies \
  | tee test/login_cookie \
  | grep "msg = user authenticated by token"

# Check that logged in only pages work
curl --url "https://$SINGULARITY_HOSTNAME/cgit" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie test/login_cookies \
  | tee test/logged_in_cgit \
  | grep "Kernel Development Learning Pipeline Git Repositories"

# Check that login target redirect works
curl --url "https://$SINGULARITY_HOSTNAME/login?target=/cgit" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie test/login_cookies \
  --location \
  | tee test/logged_in_cgit \
  | grep "Kernel Development Learning Pipeline Git Repositories"

# Check that login target blocks other hosts
curl --url "https://$SINGULARITY_HOSTNAME/login?target=https://example.com" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie test/login_cookies \
  --location \
  --no-fail \
  | tee test/login_block_csrf \
  | grep "<h1>HTTP ERROR 400: BAD REQUEST</h1>"

# Verify that cgit plain view block works
curl --url "https://$SINGULARITY_HOSTNAME/cgit/Singularity/plain" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie test/login_cookies \
  --no-fail \
  | tee test/cgit_plain_block \
  | grep '<h1>HTTP ERROR 404: NOT FOUND</h1>'




# Check that accessing logged in only pages without cookie redirects to login
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie test/login_cookies \
  | tee test/logged_in_dashboard \
  | grep "dashboard in development, check back later"

curl --url "https://$SINGULARITY_HOSTNAME/cgit" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --location \
  | tee test/unlogged_in_cgit \
  | grep "msg = welcome, please login"


curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --location \
  | tee test/unlogged_in_dashboard \
  | grep "msg = welcome, please login"


# Check that logout works
curl --url "https://$SINGULARITY_HOSTNAME/logout" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --location \
  --cookie test/login_cookies \
  | tee test/logout \
  | grep "msg = welcome, please login"

# Check that list of sessions is empty after logging out
orbit/warpdrive.sh -l \
  | tee test/sessions_logged_out_empty \
  | diff /dev/stdin <(echo "Sessions:")

# Verify that cookie is no longer valid
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie test/login_cookies \
  | tee test/login_stale_cookie \
  | grep "msg = welcome, please login"

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
To: "other@$SINGULARITY_HOSTNAME" <other@$SINGULARITY_HOSTNAME>$CR
$CR
To whom it may concern,$CR
$CR
Bottom text$CR
EOF
) | tee test/smtp_send_email \
  | diff <(printf "") /dev/stdin

# Check that the user can send an email to multiple recipients
(
curl --url "smtps://$SINGULARITY_HOSTNAME" \
  --unix-socket ./socks/smtps.sock \
  "${CURL_OPTS[@]}" \
  --mail-from "user@$SINGULARITY_HOSTNAME" \
  --mail-rcpt "other@$SINGULARITY_HOSTNAME" \
  --mail-rcpt "other1@$SINGULARITY_HOSTNAME" \
  --upload-file - \
  --user "user:${REGISTER_PASS}" <<EOF
Subject: Message Subject$CR
To: "other@$SINGULARITY_HOSTNAME" <other@$SINGULARITY_HOSTNAME>$CR
To: "other1@$SINGULARITY_HOSTNAME" <other1@$SINGULARITY_HOSTNAME>$CR
$CR
To whom it may concern,$CR
$CR
Bottom text$CR
EOF
) | tee test/smtp_send_email_multi_recipients \
  | diff <(printf "") /dev/stdin

# Check that the user can send an email with Cc (carbon copy) recipients
(
curl --url "smtps://$SINGULARITY_HOSTNAME" \
  --unix-socket ./socks/smtps.sock \
  "${CURL_OPTS[@]}" \
  --mail-from "user@$SINGULARITY_HOSTNAME" \
  --mail-rcpt "other@$SINGULARITY_HOSTNAME" \
  --mail-rcpt "other1@$SINGULARITY_HOSTNAME" \
  --upload-file - \
  --user "user:${REGISTER_PASS}" <<EOF
Subject: Message Subject$CR
To: "other@$SINGULARITY_HOSTNAME" <other@$SINGULARITY_HOSTNAME>$CR
Cc: "other1@$SINGULARITY_HOSTNAME" <other1@$SINGULARITY_HOSTNAME>$CR
$CR
To whom it may concern,$CR
$CR
Bottom text$CR
EOF
) | tee test/smtp_send_email_multi_recipients \
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
${DOCKER} exec singularity_pop_1 /usr/local/bin/restrict_access /var/lib/email/journal/journal -d resu

# Update list of email to include new message
${DOCKER} exec singularity_pop_1 /usr/local/bin/init_journal /var/lib/email/journal/journal /var/lib/email/journal/temp /var/lib/email/mail

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
${DOCKER} exec singularity_pop_1 /usr/local/bin/restrict_access /var/lib/email/journal/journal -a resu

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

# Check that we can reset a student's password
orbit/warpdrive.sh -u user -c

# Check that login fails with their old creds after their password is cleared
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "username=user&password=${REGISTER_PASS}" \
  | tee test/clear_login_fail \
  | grep "msg = authentication failure"

# Check that re-registration succeeds
curl --url "https://$SINGULARITY_HOSTNAME/register" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --data "student_id=1234" \
  | tee test/clear_reregister \
  | grep "msg = welcome to the classroom"

REREGISTER_PASS="$(sed -nr 's/.*Password: ([^<]*).*/\1/p' < test/clear_reregister | tr -d '\n')"

# Check that login succeeds with new credentials
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie-jar test/new_login_cookies \
  --data "username=user&password=${REREGISTER_PASS}" \
  | tee test/clear_login_success \
  | grep "msg = user authenticated by password"

# Force log out user
orbit/warpdrive.sh -u user -d

# Verify that cookie is no longer valid after force logout
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie test/new_login_cookies \
  | tee test/delete_session_login_fail \
  | grep "msg = welcome, please login"

# We expect that these commands will fail so putting ! in front makes
# succeeding an error and failing a success as far as set -e is concerned

# Verify that we cannot create a student with duplicate name
(! orbit/warpdrive.sh -u user -i 12345 -n 2>&1 \
  | tee test/create_duplicate_username \
  | grep "cannot create user with duplicate field")

# Verify that we cannot create a student with duplicate id
(! orbit/warpdrive.sh -u foo -i 1234 -n 2>&1 \
  | tee test/create_duplicate_id \
  | grep "cannot create user with duplicate field")

# Check that we can withdraw a student
orbit/warpdrive.sh -u user -w

# Check that list of users (roster) is empty after withdrawal
orbit/warpdrive.sh -r \
  | tee test/roster_withdrawn_empty \
  | diff /dev/stdin <(echo "Users:")

# Verify that we cannot delete a user a second time
(! orbit/warpdrive.sh -u foo -w 2>&1 \
  | tee test/withdrawl_nou \
  | grep "no such user")

# Verify that we cannot reset password of nonexistent user
(! orbit/warpdrive.sh -u foo -c 2>&1 \
  | tee test/clear_nou \
  | grep "no such user")

# Verify that we cannot force log out a user with no sessions
(! orbit/warpdrive.sh -u foo -d 2>&1 \
  | tee test/logout_nou \
  | grep "No sessions belonging to that user found")

orbit/warpdrive.sh \
  | tee test/warpdrive_usage \
  | grep 'usage:'

(! orbit/warpdrive.sh -n ) 2>&1 \
  | tee test/warpdrive_missing_args \
  | grep 'Need username and student id. Bye.'
