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
00000010: 18c0 f133 0909 8908 41ea e0a5 4837 1609  ...3....A...H7..
00000020: 419c 12a6 562a 4519 1029 2d21 0c4c 9151  A...V*E..)-!.L.Q
00000030: ae60 9138 d477 1130 c273 7429 efc3 d29d  .`.8.w.0.st)....
00000040: f7e8 54d5 311c 8256 210c 456d ddff 4fb2  ..T.1..V!.Em..O.
00000050: bf73 eeec dc7d 3e0f 27bb 1fed 0566 b1b3  .s...}>.'....f..
00000060: 279e 5025 b6b2 bc9c 44ef a758 f1aa c3bd  '.P%....D..X....
00000070: f096 57bc 6ab5 e6d5 6a2b a2e2 552a 7190  ..W.j...j+..U*q.
00000080: 95a7 ec94 35d0 c68f a414 f17f 3ed8 6e5c  ....5.......>.n\
00000090: fd3f 6a7b ab11 1825 3ff6 a39e 6fe4 4b31  .?j{...%?...o.K1
000000a0: 2b1c 47bc 89f3 2184 136f c53b 4d33 f196  +.G...!..o.;M3..
000000b0: bd73 ec3c e2f2 8e58 8c2e 4ae5 6fa2 307d  .s.<...X..J.o.0}
000000c0: 25ca 99f2 65f9 a2f4 7de6 ebcc 97e9 abd2  %...e...}.......
000000d0: 65e9 f36f 1c08 0000 0080 ffdb d9ab 7cde  e..o..........|.
000000e0: 9d9b 73ce 378c bfd7 55a1 3a1e 6815 691b  ..s.7...U.:.h.i.
000000f0: a7d6 9af5 d556 5db6 56df 36ea d2fe 2a5f  .....V].V.6...*_
00000100: 140b 91da 0fb4 897c 13f4 c376 d091 4168  .......|...v..Ah
00000110: d4be 8ae4 5114 f4fc e854 1eaa d385 6241  ....Q....T....bA
00000120: 9b41 4785 66d8 c0a8 1323 7736 d7b7 76ea  .AG.f....#w6..v.
00000130: 72f3 7d4b 6eee 341a 718b e105 43bf a746  r.}Kn.4.q...C..F
00000140: d51f f95a 1ff7 a39b f36d c5bc dc6e 35d7  ...Z.....m...n5.
00000150: d75a 4b85 9cbb 36e7 8820 eca8 13fd a91b  .ZK...6.. ......
00000160: 2fd4 dafe c0f4 93e3 b6ed 6fbb 6a4b c5a5  /.........o.jK..
00000170: a947 9de0 d952 e14c 66af 13f4 2c49 9056  .G...R.Lf...,I.V
00000180: 5ac7 23d6 364e de4b 90fd 354e 90bc 61fa  Z.#.6N.K..5N..a.
00000190: 872a bcee fc87 e6fa bbd5 e6ae dca8 ef2e  .*..............
000001a0: dcd6 8f19 bf6d a64e 8e82 38ab 91f2 bbbf  .....m.N..8.....
000001b0: 2621 f7d0 986c 9fda 555b ca2f 4d3e ea04  &!...l..U[./M>..
000001c0: cf96 7267 cf9d bceb bace b99b 2421 c94c  ..rg........$!.L
000001d0: b29b b837 fcdb c931 723e 8cbd dbc7 9d03  ...7...1r>......
000001e0: 5f1f dcbf d923 e791 4dc0 7c26 e7be 7647  _....#..M.|&..vG
000001f0: 8de7 660a 2421 3b3f 31be a997 84e1 5a7e  ..f.$!;?1.....Z~
00000200: 6af8 8894 86bb d93f fa94 0200 0000 0080  j......?........
00000210: 2796 bce0 67fd 0f00 0000 0040 aab1 fe07  '...g......@....
00000220: 0000 0000 20fd f8fe 1f00 0000 0080 f4e3  .... ...........
00000230: fd3f 0000 0000 00e9 c7fa 1f00 0000 0080  .?..............
00000240: f4e3 fb7f 0000 0000 00d2 8ff7 ff00 0000  ................
00000250: 0000 a41f eb7f 0000 0000 0000 0000 0000  ................
00000260: 0000 0000 0000 0000 00f8 3bfd 00af 11e8  ..........;.....
00000270: e900 c800 00                             .....
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
