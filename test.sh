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
00000000: 1f8b 0800 0000 0000 0003 edda 5d4f d350  ............]O.P
00000010: 18c0 f196 b76e c826 5e2c 8d72 735c 24ba  .....n.&^,.rs\$.
00000020: 2064 2881 186e 18d8 e8e2 1c32 ba04 6e5c   d(..n.....2..n\
00000030: 4a56 a511 366c bb80 37c4 f151 fc28 c60f  JV..6l..7..Q.(..
00000040: 665f f6d2 1554 bc40 49f3 ff25 5b7b 5efa  f_...T.@I..%[{^.
00000050: 9c9d e774 4b4e bab6 7d60 b94b cd03 e906  ...tKN..}`.K....
00000060: 153d ab2b 2bc1 7139 762c 2e3f f3df c3f3  .=.++.q9v,.?....
00000070: 9077 beb6 525c 9544 f126 3f54 5fc7 710d  .w..R\.D.&?T_.q.
00000080: db1b f25f 8c75 0bed ee54 2cd7 141f daf6  ..._.u...T,.....
00000090: b1e1 8ae7 d2ac 24cb d286 105e 53ca 7b4d  ......$....^S.{M
000000a0: 47ba fae5 8948 59be 46f8 94b4 647f cb64  G....HY.F...d..d
000000b0: 37a4 f49d 1fd2 ddcd ecf7 eceb ccd7 ecbd  7...............
000000c0: cc83 99f3 9947 5e15 0000 0080 bff4 3ead  .....G^.......>.
000000d0: a80b 39b9 9bb6 5a4d f3ac e398 76c3 713b  ..9...ZM....v.q;
000000e0: 4db3 e536 aca6 5f9c deaa 6925 5d13 f56a  M..6.._...i%]..j
000000f0: 79a7 ae89 72f5 a5b6 27f2 b18e 79b1 5d0d  y...r...'...y.].
00000100: 2bf3 e249 3e52 5fd8 4b29 ea63 2fbe 3c8c  +..I>R_.K).c/.<.
00000110: efbf b58c 63d3 3fa6 7f1d bddf 6d34 f6a0  ....c.?.....m4..
00000120: b6d0 bdaf 286a 2e27 5fe4 5ce3 e028 88e6  ....(j.'_.\..(..
00000130: bf52 bd88 7a69 b3a2 0daf f33f 63b9 aa6b  .R..zi.....?c..k
00000140: afb4 9aa8 6eeb a25a af54 c4bb 5af9 6da9  ....n..Z.T..Z.m.
00000150: b62f de68 fb4f c530 b4d0 b53d 7dd0 cb6b  ./.h.O.0...=}..k
00000160: 3939 6d1e 1ace e1e5 8668 06fc b682 d8d5  99m......h......
00000170: 6be5 2dbd 39a5 a88b 7372 3713 ccda 311d  k.-.9...sr7...1.
00000180: c76a b706 33ea 9595 2be7 1eef 1c4e bf57  .j..3...+....N.W
00000190: 1bcb 4076 4251 e7bc 619c 2003 bd3e bdc3  ..@vBQ..a. ..>..
000001a0: e468 1e22 01dc f627 b315 9bcb b553 619e  .h."...'.....Sa.
000001b0: 9d58 f697 bcf0 8257 06f5 fd69 2f4e 4ea9  .X.....W...i/NN.
000001c0: a539 590a 67fd f9c8 db1d 368c 8edb 0eca  .9Y.g.....6.....
000001d0: 8dfe cc96 7b27 5352 b82f 94ce c615 756d  ....{'SR./....um
000001e0: 5eee 3e0c fad9 e647 cb71 6dc3 8d66 215a  ^.>....G.qm..f!Z
000001f0: 3971 65de aebc 2c4c 5eb4 6934 83e7 638a  9qe...,L^.i4..c.
00000200: baee 8d5c b83c f270 69a3 d5e3 7f1e 3bfe  ...\.<.pi.....;.
00000210: ad88 8f1e fd76 74d7 6545 9d9f 972f 5e04  .....vt.eE.../^.
00000220: 2b18 ed1a 3d1f 1b5d cb78 c46b dcdb f11b  +...=..].x.k....
00000230: 35ba a4bf b9ef 0dc7 396d dbf1 6bfa cb9d  5.......9m..k...
00000240: f117 6ff6 bffe 7c01 0000 0000 801b 163c  ..o...|........<
00000250: e067 ff0f 0000 0000 40a2 b1ff 0700 0000  .g......@.......
00000260: 0020 f9f8 ff3f 0000 0000 00c9 c7f3 7f00  . ...?..........
00000270: 0000 0000 928f fd3f 0000 0000 00c9 c7ff  .......?........
00000280: ff01 0000 0000 483e 9eff 0300 0000 0090  ......H>........
00000290: 7cec ff01 0000 0000 0000 0000 0000 0000  |...............
000002a0: 0000 0000 0000 e076 fa09 3ff3 0562 00c8  .......v..?..b..
000002b0: 0000                                     ..
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
