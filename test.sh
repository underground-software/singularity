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
	${DOCKER} run --rm -v singularity_email:/var/lib/email alpine:3.19 sh -c 'rm -f /var/lib/email/mail/* /var/lib/email/logs/*'
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
00000000: 1f8b 0800 0000 0000 0003 edda 4d8f d240  ............M..@
00000010: 18c0 f176 79a9 9af0 7221 3d70 9970 51a2  ...vy...r!=p.pQ.
00000020: bb01 25ae 37c5 b531 44ec ba6c 49d8 8ba4  ..%.7..1D..lI...
00000030: a4dd 6ce3 2eac 6d89 eb11 13bf 88df c6ab  ..l...m.........
00000040: dfc1 efe0 d119 282f 4b34 d90b 6af0 ff4b  ......(/K4..j..K
00000050: 3a33 cf74 78a6 0fe9 6502 a370 10c4 7bde  :3.tx...e..p..{.
00000060: 40db a09a f4b8 d198 f6f5 b5be 56db 574d  @...........V.WM
00000070: 32ae 25e3 fd46 fda1 266a 9b7c a8b9 7114  2.%..F..&j.|..q.
00000080: bba1 dcf2 4fec f50f 3a3e 6a07 b12f 4e47  ....O...:>j../NG
00000090: e185 1b8b 475a 51d3 75ed 9910 f256 465e  ....GZQ.u....VF^
000000a0: c6ca 5215 a757 62fd 06e9 33da 5ef8 2557  ..R..Wb...3.^.%W
000000b0: f8a1 6573 9fb5 c293 c2d7 fcb7 fcd3 dc77  ..es...........w
000000c0: 1900 0000 00c0 ffe8 6dd6 30ef 97f4 c9ed  ........m.0.....
000000d0: 60e8 f957 e3c8 0ffb 513c f6fc 61dc 0f3c  `..W....Q<..a..<
000000e0: 151a 071d abe9 58a2 6bb7 8eba 9668 d92f  ......X.k....h./
000000f0: ac9e a8ac 2dac 8843 7b36 5911 f72a 2bf3  ....-..C{6Y..*+.
00000100: d55e c630 efca fcfa 32bf 6a86 ee85 affa  .^.0....2.j.....
00000110: ecef b3cf 975d cfbd 98ad 4e8a 69c3 2c95  .....]....N.i.,.
00000120: f44f a9d8 1d9c 4fb3 a92b 9364 749a cfdb  .O....O..+.dt...
00000130: d6f2 73ea 195b b663 bdb4 3ac2 3e74 84dd  ..s..[.c..:.>t..
00000140: 6db7 c59b 4eeb 75b3 7322 5e59 270f c432  m...N.u.s"^Y'..2
00000150: b570 ac9e b358 25ef 5c7e f0ce dce8 6c76  .p...X%.\~....lv
00000160: 43c6 ab85 aba9 aa38 763a ad03 c74b 19e6  C......8v:...K..
00000170: 6e59 9fe4 a6c5 467e 1405 a3e1 a290 244e  nY....F~......$N
00000180: ffb2 e4f5 c5b3 aa93 d9b5 c2f3 ba61 96e5  .............a..
00000190: 36d1 b4f0 644d d2ed 5c2f 7f25 413c 7ae7  6...dM..\/.%A<z.
000001a0: 0fd7 6abb f137 e05f 5d06 e1c7 8a90 c9db  ..j..7._].......
000001b0: 8bf9 79d9 bb3b 59b3 59d6 b559 d5ef cfe5  ..y..;Y.Y..Y....
000001c0: a9be ef8e e3d1 34ee cf2b ab27 8394 7ceb  ......4..+.'..|.
000001d0: 6ea9 572f a79a e25f 7dfb 0100 0000 00c0  n.W/..._}.......
000001e0: 86dd 510d e77f 0000 0000 00b6 1ae7 7f00  ..Q.............
000001f0: 0000 0000 b61f ffff 0700 0000 0060 fbf1  .............`..
00000200: fb3f 0000 0000 00db 8ff3 3f00 0000 0000  .?........?.....
00000210: 0000 6ca7 9f2d 67a0 8900 7800 00         ..l..-g...x..
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
orbit/warpdrive.sh -u user -i 1234 -n

add_cleanup "orbit/warpdrive.sh -u user -w"

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

# Remove the email we just sent
add_cleanup nuke_mail

# Check that the user can get the most recent message sent to the server
curl --url "pop3s://$SINGULARITY_HOSTNAME/1" \
  --unix-socket ./socks/pop3s.sock \
  "${CURL_OPTS[@]}" \
  --user "user:${REGISTER_PASS}" \
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
