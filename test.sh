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
00000010: 18c0 f196 b76e c826 5e90 2672 735c 4274  .....n.&^.&rs\Bt
00000020: 51c8 5002 31dc 30b0 d1c5 3964 9404 6e5c  Q.P.1.0...9d..n\
00000030: 4a56 a511 366c bb80 37c6 71e3 f7f0 a378  JV..6l..7.q....x
00000040: ef77 f2b4 dd4b 5751 8909 4a9a ff2f d9da  .w...KWQ..J../..
00000050: 737a fa9c 3ee7 744b 4eda b67b e8f8 4bcd  sz..>.tKN..{..K.
00000060: 43e5 1a95 a4d5 9595 70bb 9cd8 9696 1f07  C.......p.......
00000070: dfd1 7e44 eeaf ad94 5615 51ba ce8b eaeb  ..~D....V.Q.....
00000080: 78be e5ca 2eff 455f 37d0 ee4e d5f1 6df1  x.....E_7..N..m.
00000090: b6ed 9e58 be78 a2cc 2aaa aa6c 0821 0f65  ...X.x..*..l.!.e
000000a0: e467 3ad6 3428 4fc4 caea 15c2 6794 25f7  .g:.4(O.....g.%.
000000b0: 6b2e bfa1 646f 7d57 6e6f e6bf e55f e43e  k...do}Wno..._.>
000000c0: e7ef e4ee ce7c 9959 9455 0000 0000 fed6  .....|.Y.U......
000000d0: 9bac a63f 9c53 bb59 a7d5 b4cf 3b9e ed36  ...?.S.Y....;..6
000000e0: 3cbf d3b4 5b7e c369 06c5 e9ad ba51 360d  <...[~.i.....Q6.
000000f0: b157 abec ec19 a252 7b66 ec8b 42a2 6141  .W.....R{f..B.aA
00000100: 6cd7 a2ca 8278 5088 d517 f733 9a7e 5fc6  l....xP....3.~_.
00000110: 5787 f183 af96 7562 07db ecaf a3f7 9b8d  W.....ub........
00000120: c61e d416 bbb3 9aa6 cfcd a917 e3be 7578  ..............ux
00000130: 1c46 0b3e 995e 44b3 bc59 3586 e705 d758  .F.>.^D..Y5....X
00000140: a999 c673 a32e 6adb a6a8 ed55 abe2 75bd  ...s..j....U..u.
00000150: f2aa 5c3f 102f 8d83 4762 185a 98c6 be39  ..\?./..Gb.Z...9
00000160: 6825 8f9c 9e35 8f2c ef28 3a20 cbf1 c483  h%...5.,.(: ....
00000170: aaa2 d835 eb95 2db3 39a5 e98b f36a 3717  ...5..-.9....j7.
00000180: 26eb d99e e7b4 5b83 447a 65ed d294 938d  &.....[.Dze.....
00000190: a3ac 7bb5 89c4 f313 9a3e 2fbb f1c2 c47b  ..{......>/....{
000001a0: 6d7a 9bc9 d1f4 6301 fcf6 7bbb 95c8 edca  mz....c...{.....
000001b0: 2360 9f9f 3aee c782 90c1 ab83 fa7e da8b  #`..:........~..
000001c0: 9353 7a79 5e55 a2ac 3f1c cbd5 61c3 eaf8  .Szy^U..?...a...
000001d0: edb0 dce8 67b6 dcdb 9952 a275 a172 3eae  ....g....R.u.r>.
000001e0: e96b 0b6a f75e d8ce b5df 399e ef5a 7e7c  .k.j.^....9..Z~|
000001f0: 14e2 9513 978e dba5 a745 8317 3f34 3a82  .........E..?4:.
00000200: 9fc6 347d 5df6 5cfc b9e7 e1d4 c6ab c7ff  ..4}].\.........
00000210: dc77 f2c7 90ec 3dfe a3e8 aeab 9abe b0a0  .w....=.........
00000220: 5e3c 0d67 30de 34be 3f36 3a97 c988 57b8  ^<.g0.4.?6:...W.
00000230: a593 376a 7c4a 7f73 bb5b 9e77 d676 93e7  ..7j|J.s.[.w.v..
00000240: f4a7 3b17 4cde ec7f fdd7 0200 0000 0000  ..;.L...........
00000250: d72c 7cc0 cffa 1f00 0000 0080 5463 fd0f  .,|.........Tc..
00000260: 0000 0000 40fa f1fe 3f00 0000 0000 e9c7  ....@...?.......
00000270: f37f 0000 0000 00d2 8ff5 3f00 0000 0000  ..........?.....
00000280: e9c7 fbff 0000 0000 00a4 1fcf ff01 0000  ................
00000290: 0000 483f d6ff 0000 0000 0000 0000 0000  ..H?............
000002a0: 0000 0000 0000 0000 0070 33fd 007a eebd  .........p3..z..
000002b0: 9700 c800 00                             .....
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
