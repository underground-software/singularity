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
00000000: 1f8b 0800 0000 0000 0003 edda bf4e db40  .............N.@
00000010: 1cc0 f133 84fc 1349 582a 0f55 a41b 1b09  ...3...IX*.U....
00000020: 9138 043a 5495 9aa2 0ca8 292d 940c 4c91  .8.:T.....)-..L.
00000030: a35c c102 1cea 7314 18c3 9354 799f 0e55  .\....s....Ty..U
00000040: df80 a7e8 58c7 e510 2041 3214 b5b5 be1f  ....X... A2.....
00000050: c9be b3fd b37d f73b 7b38 d983 a0e7 856b  .....}.;{8.....k
00000060: fd9e 7842 b5c8 66a3 1197 cebd b2e6 d4a7  ..xB..f.........
00000070: 6be1 3436 9d7a 7dc3 5977 3644 cda9 d51a  k.46.z}.Yw6D....
00000080: 2f85 ac3d 65a3 8ca1 0edd 404a 11dd f3d1  /..=e.....@J....
00000090: b859 c7ff 539f 76db 5ea8 e4e7 4170 ea86  .Y..S.v.^...Ap..
000000a0: 725d ac08 cb12 6fa2 7c08 6145 4bfe 56e8  r]....o.|.aEK.V.
000000b0: 62b4 a46e 6d5b 735c de12 6bc1 a450 fa29  b..nm[s\..k..P.)
000000c0: 72cb 57a2 942a 7d2b 4d8a 0bc5 1fc5 c9f2  r.W..*}+M.......
000000d0: 55e1 7be1 eb9f eb07 0000 0000 0831 7e95  U.{..........1~.
000000e0: c9d8 e5b2 75b9 1dba bd13 e5ab d150 ab40  ....u........P.@
000000f0: 9b32 bbb5 d76a eeb7 e47e f36d bb25 cd5e  .2...j...~.m.%.^
00000100: f922 9f0b d4a1 a7c3 c00d bd81 dff5 fad2  ."..............
00000110: f343 75a8 0279 1678 a76e 7021 8fd5 c56a  .Cu..y.x.np!...j
00000120: 3ea7 c361 5ff9 e134 200a f6fc 43d9 d9d9  >..a_..4 ...C...
00000130: deed b4e4 ce87 7db9 d369 b7a3 98e9 257d  ......}..i....%}
00000140: f754 3d1c 71e6 6a3d 1a04 37d7 3087 2ad5  .T=.q.j=..7.0.*.
00000150: 5cda de2a 5bc2 f3fb ea5c 7f39 8926 6b5d  \..*[....\.9.&k]
00000160: 7718 0ee2 edae 696e b76e 6af9 6a76 ae13  w.....in.nj.jv..
00000170: 1c53 cb8d cba9 dff9 29c4 f9d1 4aeb a8c3  .S......)...J...
00000180: da94 4b77 f263 f646 f991 d7c2 c1b1 f24d  ..Kw.c.F.......M
00000190: bb3f ee6d bf6f ee1d c877 ad83 d59b 8899  .?.m.o...w......
000001a0: dd37 81ea fccc 8b12 1b28 f7e4 5606 d28f  .7.......(..V...
000001b0: 75c8 34a8 5b37 b54c 7569 ae13 1c53 4b8f  u.4.[7.Lui...SK.
000001c0: 9f5b 19db b6ad cb67 7106 e2b4 c4ab 853b  .[.....gq......;
000001d0: 7dbf 7930 1e7c 16e6 18e7 51ff c8d5 47f7  }.y0.|....Q...G.
000001e0: 87f9 91e7 a852 594c dbaf ed87 ba73 3dfc  .....RYL.....s=.
000001f0: 7191 aa2c cc0e 75e2 623a 97cf 4edf 8ec2  q..,..u.b:..N...
00000200: 74b5 f257 5f50 0000 0000 00f0 c4e2 0ffc  t..W_P..........
00000210: ccff 0100 0000 0048 34e6 ff00 0000 0000  .......H4.......
00000220: 241f ffff 0300 0000 0090 7c7c ff07 0000  $.........||....
00000230: 0000 20f9 98ff 0300 0000 0090 7cfc ff0f  .. .........|...
00000240: 0000 0000 40f2 f1fd 1f00 0000 0080 e463  ....@..........c
00000250: fe0f 0000 0000 0000 0000 0000 0000 0000  ................
00000260: 0000 0000 00ff a65f a15a b1c9 00c8 0000  ......._.Z......
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
