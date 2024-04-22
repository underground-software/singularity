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
00000000: 1f8b 0800 0000 0000 0003 edda c14e db30  .............N.0
00000010: 18c0 7187 9696 560a 459a b45c 86e4 e390  ..q...V.E..\....
00000020: 104d dac2 6dd2 58d5 035a c746 690f 9caa  .M..m.X..Z.Fi...
00000030: 54f5 4604 4d59 920a 384d e539 7619 efc3  T.F.MY..8M.9v...
00000040: 654f b3d3 b434 c388 6e82 f6b0 6a5b f4ff  eO...4..n...j[..
00000050: 49b1 9dd8 69fd d9c9 c172 8641 cf8b b6fa  I...i....r.A....
00000060: 3db1 4076 6ca7 564b 72e7 97dc 762a 9354  =.@vl.VKr...v*.T
00000070: 38b5 1da7 52d9 aed8 5547 d88e 6dd7 aa42  8...R...UG..m..B
00000080: da8b ec94 360a 2337 9052 c4ff f968 bb59  ....6.#7.R...h.Y
00000090: f5ff a9c3 83a6 1729 f97e 180c dc48 56c5  .......).~...HV.
000000a0: 9a30 0cf1 321e 0f21 8cf8 28de 6b9a 898f  .0..2..!..(.k...
000000b0: ecbd 7363 8e9f 37c4 5670 6d96 be89 8299  ..sc..7.Vpm.....
000000c0: 11a5 4ce9 a674 6d7e 5ffd bafa c5cc 9837  ..L..tm~_......7
000000d0: e6e7 3f18 0800 0000 00cc 367e 9acf 5beb  ..?.......6~..[.
000000e0: ebc6 f853 e4f6 4e95 afce 47a1 0a42 9daf  ...S..N...G..B..
000000f0: d45b 8ddd 7643 b677 5f35 1b52 5f95 cf8b  .[..vC.w_5.R_...
00000100: 8530 1af5 951f 75bd be8c d445 243b fb7b  .0....u....E$;.{
00000110: 079d 86dc 7fdb 96fb 9d66 73b3 5898 34f5  .........fs.X.4.
00000120: dd81 7aa8 fecc 0dc3 f361 707b bfae d890  ..z......ap{....
00000130: 87ed d65e bd5d 2ee4 acfa ba21 3cbf af2e  ...^.].....!<...
00000140: c28f a7f1 42ad eb8e a261 72de d53d e956  ....B....ar..=.V
00000150: 74a9 585e 99eb 0647 970a 6399 4d42 bf7a  t.X^...G..c.MB.z
00000160: 9284 1eaa 30f4 867e a8f3 e5a9 d0f5 d538  ....0..~.......8
00000170: 7479 2b1a 9e28 ff67 e7df b5f6 deec b68e  ty+..(.g........
00000180: e4eb c6d1 e65d fd8c f875 3375 71e6 0597  .....]...u3uq...
00000190: 3250 eee9 ef83 907b 2c26 dda7 6e45 97f2  2P.....{,&..nE..
000001a0: e5e5 b96e 7074 2937 7e66 e42d cb32 aeac  ...npt)7~f.-.2..
000001b0: 6410 9291 4992 a5a9 f0ef a63d 9e6e cf8f  d...I......=.n..
000001c0: d407 15c8 b3c0 1bb8 71cf 4fd4 e53c b37d  ........q.O..<.}
000001d0: de3f 76c3 e3e9 c9de 7ce8 39d2 03b0 91c9  .?v.....|.9.....
000001e0: 592f ac87 e2b9 7d04 922c bbb1 34bb a993  Y/....}..,..4...
000001f0: 6493 b5fc cae4 e137 27c9 da5f 7dff 0000  d......7'.._}...
00000200: 0000 00c0 8225 1bfc acff 0100 0000 0048  .....%.........H
00000210: 35d6 ff00 0000 0000 a41f dfff 0300 0000  5...............
00000220: 0090 7eec ff03 0000 0000 907e acff 0100  ..~........~....
00000230: 0000 0048 3fbe ff07 0000 0000 20fd d8ff  ...H?....... ...
00000240: 0700 0000 0020 fd58 ff03 0000 0000 0000  ..... .X........
00000250: 0000 0000 0000 0000 0000 0000 c0bf e907  ................
00000260: 0823 875f 00c8 0000                      .#._....
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
