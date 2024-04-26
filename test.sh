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
00000000: 1f8b 0800 0000 0000 0003 edda db4f d350  .............O.P
00000010: 1cc0 f196 5bc7 6503 9f1a 1349 8e7b 5182  ....[.e....I.{Q.
00000020: c2a6 0b3c f822 6263 1667 9151 1230 26b3  ...<."bc.g.Q.0&.
00000030: 6445 1a61 c39e 4ef0 71fc 05be f9ee 9fe4  dE.a..N.q.......
00000040: 837f 8fbd d051 0a2a 8941 49f3 fd24 6b7b  .....Q.*.AI..$k{
00000050: 7a6e 3dbf d32e 3969 bbde 8eeb 2fb4 7794  zn=...9i..../.w.
00000060: 6b54 092c d56a d1be 9ad9 57aa 8fc2 6d7c  kT.,.j....W...m|
00000070: 1c0b 8e97 6b95 2545 54ae f3a2 123d e9db  ....k.%ET....=..
00000080: 5ed0 e5bf e8eb 06da 586f b8be 2376 bbde  ^.......Xo..#v..
00000090: 81ed 8bc7 ca8c a2aa ca53 2182 ac42 f09b  .........S!..B..
000000a0: 4815 0dd3 23a9 b47a 85e6 0bca 82f7 ad58  H...#..z.......X
000000b0: 7aab 8c4f 7e57 a6cd d28f 52bb f8b5 345f  z..O~W....R...4_
000000c0: 5c9c fa32 550b 4e01 0000 00f8 2bef c635  \..2U.N.....+..5
000000d0: 7d5e 57fb 936e a7ed 1cf7 a4e3 b5a4 df6b  }^W..n.........k
000000e0: 3b1d bfe5 b6c3 a49c 586d 1a2b 9621 36cd  ;.......Xm.+.!6.
000000f0: fafa a621 eae6 7363 4b94 3325 cb62 cd8c  ...!..scK.3%.b..
00000100: 4fca b2b8 5f4e 65cc bd29 68fa bda0 87e1  O..._Ne..)h.....
00000110: b31e c24d c73e 70a2 f2e3 bf6e 3f29 9769  ...M.>p....n?).i
00000120: 7d70 7aae 7f47 d374 5d57 4f74 dfde d98f  }pz..G.t]WOt....
00000130: db8b 3685 d346 ad95 670d 2355 35bc d2ba  ..6..F..g.#U5...
00000140: 6919 2f8c a630 d72c 616e 361a e275 b3fe  i./..0.,an6..u..
00000150: 6aa5 b92d 5e1a db0f c459 ebc2 32b6 ac41  j..-^....Y..2..A
00000160: a920 e7f0 a8bd 67cb bd8b 19e9 3884 7973  . ....g.....8.ys
00000170: 62c3 6ad6 57ad dd31 4d7f 38ab f6a7 a3a1  b.j.W..1M.8.....
00000180: 4b47 4ab7 db19 8cea 342d b54b 0390 2d1d  KGJ.....4-.K..-.
00000190: c720 a993 09c3 ad11 4d9f 0d3a ea45 6148  . ......M..:.EaH
000001a0: 0a25 fbd1 f3c1 48b7 e177 3f38 9dcc 80ae  .%....H..w?8....
000001b0: 1c0f e7f8 d0f5 3e97 45d0 7a63 703e 19fb  ......>.E.zcp>..
000001c0: e2e8 98be 3aab 2af1 d03f ee07 ebc6 96dd  ....:.*..?......
000001d0: f3bb 51ba 955c 43ab 9a1c 8d29 f19a 5139  ..Q..\C....)..Q9
000001e0: 1cd6 f4e5 602c b7a3 929e f3de 95be 67fb  ....`,........g.
000001f0: e958 749c a368 4647 2e8d dca5 55e2 f025  .Xt..hFG....U..%
00000200: 15cf 87ef d390 a63f 097a bc7b b1c7 b399  .......?.z.{....
00000210: 4daa 0eff b9cf ec63 91ee 35fd 64f4 17d5  M......c..5.d...
00000220: 68da 4eaa d1b4 25c5 92fd d0f9 694b b772  h.N...%.....iK.r
00000230: 85db 387b 4fa6 27ee 37b7 b82d e551 d7cb  ..8{O.'.7..-.Q..
00000240: d649 26b5 184e d0cc 7ffd c302 0000 0000  .I&..N..........
00000250: 00d7 2c7a c1cf fa1f 0000 0000 805c 63fd  ..,z.........\c.
00000260: 0f00 0000 0040 fef1 fd3f 0000 0000 00f9  .....@...?......
00000270: c7fb 7f00 0000 0000 f28f f53f 0000 0000  ...........?....
00000280: 00f9 c7f7 ff00 0000 0000 e41f efff 0100  ................
00000290: 0000 00c8 3fd6 ff00 0000 0000 0000 0000  ....?...........
000002a0: 0000 0000 0000 0000 0000 7033 fd04 006b  ..........p3...k
000002b0: 73c3 00c8 0000                           s.....
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
