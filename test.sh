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
add_cleanup() {
	trap -- "$(
		printf '%s\n' "$1"
		# get stack is invoked in eval but shellcheck cannot tell since it is indirect
		# shellcheck disable=SC2317
		get_stack() { printf '%s\n' "$3"; }
		eval "get_stack $(trap -p EXIT)"
	)" EXIT
}

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

nuke_mail() {
	${DOCKER} run --rm -v singularity_email:/mnt alpine:3.19 sh -c 'rm -f /mnt/mail/* /mnt/logs/*'
}

# Save original contents of mail volume
${DOCKER} volume export singularity_email > test/email_orig.tar

#start with no mail and restore any saved messages once the test completes
nuke_mail
add_cleanup "${DOCKER} volume import singularity_email test/email_orig.tar"

CURL_OPTS=( \
--verbose \
--cacert test/ca_cert.pem \
--fail \
--no-progress-meter \
)

# Save original contents of orbit db volume
${DOCKER} volume export singularity_orbit-db > test/orbit_orig.tar

# Import an empty orbit db with no users or sessions
xxd -r <<- 'EOF' | gunzip | ${DOCKER} volume import singularity_orbit-db -
00000000: 1f8b 0800 0000 0000 0003 edda b14e db40  .............N.@
00000010: 18c0 f133 8484 4484 b054 5607 a41b 1b09  ...3..D..TV.....
00000020: 419c 266c 484d 5106 d494 9614 06a6 c828  A.&lHMQ........(
00000030: 57b0 0087 fa2e 0a8c f028 4c55 dfa5 0f50  W........(LU...P
00000040: f52d 983a d631 3944 5a85 3014 b5b5 fe3f  .-.:.19DZ.0....?
00000050: c9be b3ef 6cdf f7d9 1e4e 762f 3a08 cc6a  ....l....Nv/:..j
00000060: f740 3ca1 4a6c bd56 4b4a ef97 b2e2 5587  .@<.Jl.VKJ....U.
00000070: 6be1 d5d6 bd6a b5ee d5ea 7551 f12a 957a  k....j....uQ.*.z
00000080: 4dc8 ca53 0eca ea6b e347 528a f89a 0ff6  M..S...k.GR.....
00000090: 9bd6 fe9f fab0 d30a 8c92 1f7b d1a9 6fe4  ...........{..o.
000000a0: 4bb1 241c 47bc 8af3 2184 132f 857b 5d67  K.$.G...!../.{]g
000000b0: e325 736f db79 c4e9 1db1 1a5d 174b 3f44  .%so.y.....].K?D
000000c0: 7ee1 4694 0aa5 afa5 ebc5 85c5 6f8b 9f17  ~.F.........o...
000000d0: 6e8a df8b 5ffe 6020 0000 0000 f09b cb7a  n..._.` .......z
000000e0: 2ee7 2e2f 3b57 1bc6 3f38 51a1 1af4 b58a  .../;W..?8Q.....
000000f0: b42d e737 dbcd c66e 53ee 365e b79a d2ee  .-.7...nS.6^....
00000100: 952f 0af9 481d 06da 44be 097a 6127 e8ca  ./..H...D..za'..
00000110: 2034 ea50 45f2 2c0a 4efd e842 1eab 8b95   4.PE.,.N..B....
00000120: 425e 9b7e 5785 66d8 c1a8 7323 f7b6 b776  B^.~W.f...s#...v
00000130: f69a 72fb ddae dcde 6bb5 e21e c313 86fe  ..r.....k.......
00000140: a99a d47e e66b 3de8 45a3 e36d 4379 2d9f  ...~.k=.E..mCy-.
00000150: 7537 971d 1184 5d75 ae3f 9dc4 d3b6 8edf  u7....]u.?......
00000160: 37bd 64bb 6307 daa9 da5a 616d fe51 0778  7.d.c....Zam.Q.x
00000170: b696 bf7c 9eb9 cdcc 5c92 19ad b48e 43d5  ...|....\.....C.
00000180: b69c 1bcb 8cdd 1b67 468e 98de b10a 6f47  .......gF.....oG
00000190: fdbe bdf5 b6d1 de97 6f9a fb2b 77ed 5302  ........o..+w.S.
000001a0: b7dd d4f9 5910 a733 52fe c9bd e8b3 0f05  ....Y..3R.......
000001b0: 6307 d3a9 da5a 6e6d ee51 0778 b696 bd7c  c....Znm.Q.x...|
000001c0: e6e4 5cd7 75ae f249 f449 4a92 d5cc 58dc  ..\.u..I.IJ...X.
000001d0: 778f c3c4 2760 eafd 1d74 8f7c 7d34 7e7b  w...'`...t.|}4~{
000001e0: 273e 39e5 f26c d6dd 7027 0532 bae9 4991  '>9..l..p'.2..I.
000001f0: 29cf 4cef ea25 c570 2e3f 3f7c 1b8a c3d5  ).L..%.p.??|....
00000200: d25f 7d21 0100 0000 00c0 134b 3ef0 33ff  ._}!.......K>.3.
00000210: 0700 0000 0020 d598 ff03 0000 0000 907e  ..... .........~
00000220: fcff 0f00 0000 0040 faf1 fd1f 0000 0000  .......@........
00000230: 80f4 63fe 0f00 0000 0040 faf1 ff3f 0000  ..c......@...?..
00000240: 0000 00e9 c7f7 7f00 0000 0000 d28f f93f  ...............?
00000250: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000260: 0000 00fc 9b7e 02a1 8c2e aa00 c800 00    .....~.........
EOF

# Restore the old orbit db after testing completes
add_cleanup "${DOCKER} volume import singularity_orbit-db test/orbit_orig.tar"

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
orbit/warpdrive.sh \
  -u user -p pass -i 1234 -n \
  | tee test/create_user \
  | grep "credentials(username: user, password:pass)"

add_cleanup "orbit/warpdrive.sh \
  -u user -w \
  | tee test/delete_user \
  | grep 'user'"

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
  --data "username=user&password=pass" \
  | tee test/login_success \
  | grep "msg = user authenticated by password"

# Check that the user can get the empty list of email on the server
curl --url "pop3s://$SINGULARITY_HOSTNAME" \
  --unix-socket ./socks/pop3s.sock \
  "${CURL_OPTS[@]}" \
  --user user:pass \
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
  --user 'user:pass' <<EOF
Subject: Message Subject$CR
$CR
To whom it may concern,$CR
$CR
Bottom text$CR
EOF
) | tee test/smtp_send_email \
  | diff <(printf "") /dev/stdin

# Remove the email we just sent
add_cleanup nuke_mail

# Check that the user can get the most recent message sent to the server
curl --url "pop3s://$SINGULARITY_HOSTNAME/1" \
  --unix-socket ./socks/pop3s.sock \
  "${CURL_OPTS[@]}" \
  --user user:pass \
  | tee test/pop_get_message \
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
        \"password\": \"pass\"
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
