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
00000010: 18c0 f133 8484 4424 a143 e5a1 42bd b191  ...3..D$.C..B...
00000020: 10b1 4360 a92a 95a2 0ca8 292d 340c 4c91  ..C`.*....)-4.L.
00000030: a35c 8305 71c0 e708 18e1 413a f03e 5587  .\..q.....A:.>U.
00000040: be00 8fd1 b18e cb45 4005 6428 6aeb fe7f  .......E@.d(j...
00000050: 927d 67fb b373 f7e5 3c9c ce83 b0e3 474b  .}g..s..<.....GK
00000060: dd8e 7844 4e6c b55e 4f4a f756 e9b8 b5d1  ..xDNl.^OJ.V....
00000070: 5eb8 f555 b756 5b71 dde5 55e1 b88e b3e2  ^..U.V[q..U.....
00000080: 08e9 3c66 a38c a18e bc50 4a11 ffe6 bd71  ..<f.....PJ....q
00000090: 0f5d ff47 7ddc 6afa 9192 9f06 61df 8be4  .].G}.j.....a...
000000a0: b298 1796 255e c7f9 10c2 8ab7 c2b5 d0e9  ....%^..........
000000b0: 78cb 5c3b b626 78bc 2596 c28b 62f9 bbc8  x.\;.&x.%...b...
000000c0: cf5d 8a72 a6fc a57c 5112 a56f a58b b9cb  .].r...|Q..o....
000000d0: e2d7 e2e7 dfd8 1100 0000 00ff bdb3 97b9  ................
000000e0: 9cbd b060 9d6f 445e e740 05ea 78a8 55a8  ...`.oD^.@..x.U.
000000f0: 4d39 bbbe dd58 6b35 646b ed4d b321 cd59  M9...Xk5dk.M.!.Y
00000100: f9a2 900f 55cf d751 e845 fe20 68fb 5de9  ....U..Q.E. h.].
00000110: 0791 eaa9 501e 867e df0b 4fe5 be3a 5d2c  ....P..~..O..:],
00000120: e475 34ec aa20 1a05 c4c1 7ed0 933b 9b1b  .u4.. ....~..;..
00000130: 5b3b 0db9 f9be 2537 779a cd38 66f4 c8c0  [;....%7w..8f...
00000140: ebab bb23 0e3d ad8f 07e1 f819 e652 a59a  ...#.=.......R..
00000150: cfda eb0b 96f0 83ae 3ad1 4707 f154 aded  ........:.G..T..
00000160: 0da3 4172 dc36 cd6d d74c ad50 9d9d e806  ..Ar.6.m.L.P....
00000170: d7d4 f267 cf33 3ff3 f324 c98f 565a c71d  ...g.3?..$..VZ..
00000180: d6a6 9cb9 911f 7336 ce8f bc12 0df6 5560  ......s6......U`
00000190: dafd 617b e3dd daf6 ae7c dbd8 5d1c 473c  ..a{.....|..].G<
000001a0: d87d 13a8 4e0e fd38 b1bf e420 7b5f 974c  .}..N..8... {_.L
000001b0: 93da 3553 cb55 6726 bac1 35b5 ecd9 332b  ..5S.Ug&..5...3+
000001c0: 67db b675 fe34 c941 9298 6437 75a3 f7e3  g..u.4.A..d7u...
000001d0: a171 e768 98e0 9f3e eeee 797a ef76 27ef  .q.h...>..yz.v'.
000001e0: 1949 95ca 74d6 7e65 dfd5 9dab 0190 1499  .I..t.~e........
000001f0: cad4 c3a1 6e52 8ce6 f2b3 a3f7 a338 dacd  ....nR.......8..
00000200: ffd1 5714 0000 0000 003c b264 819f f93f  ..W......<.d...?
00000210: 0000 0000 00a9 c6fc 1f00 0000 0080 f4e3  ................
00000220: fb7f 0000 0000 00d2 8ff5 7f00 0000 0000  ................
00000230: d28f f93f 0000 0000 00e9 c7f7 ff00 0000  ...?............
00000240: 0000 a41f ebff 0000 0000 00a4 1ff3 7f00  ................
00000250: 0000 0000 0000 0000 0000 0000 0000 0000  ................
00000260: 0000 f83b fd00 e7f3 180e 00c8 0000       ...;..........
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
