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
00000010: 18c0 7107 4a4b 2b85 224d 5a2e 20f9 3824  ..q.JK+."MZ. .8$
00000020: 4493 8c72 9b34 56f5 80d6 b151 ca81 5395  D..r.4V....Q..S.
00000030: aa9e 8806 0d8b 5395 9da6 ee51 7887 5df6  ......S....Qx.].
00000040: 0e7b 8d5d f602 3b2e cd30 a29b 4a91 36b4  .{.]..;..0..J.6.
00000050: 2dfa ffa4 d84e 6cb7 feec e460 2551 dc0b  -....Nl....`%Q..
00000060: 93ad 7e4f dc23 37b5 b3bd 9de5 de4f b9eb  ..~O.#7......O..
00000070: f993 5478 db3b 9eef d7fd ba5b 17ae e7ba  ..Tx.;.....[....
00000080: 754f 48f7 3e07 650c 7512 c452 8af4 3f6f  uOH.>.e.u..R..?o
00000090: 6d37 affe 3f75 78d0 0a13 255f 47f1 5990  m7..?ux...%_G.Y.
000000a0: c8c7 6255 5896 789a ce87 1056 7a54 6e34  ..bUX.x....VzTn4
000000b0: 5d4c 8fc2 8d73 eb0e 3f6f 89ad f8d2 ae7e  ]L...s..?o.....~
000000c0: 1365 7b4d 54d7 aa9f ab97 2bce cad7 954f  .e{MT.....+....O
000000d0: f69a fdc5 fef8 0703 0100 0000 80df 307e  ..............0~
000000e0: 582a 39eb ebd6 f87d 12f4 4ed5 408d 865a  X*9....}..N.@..Z
000000f0: c5da e4cb 8d76 73b7 d394 9ddd 67ad a634  .....vs.....g..4
00000100: 57e5 a34a 5927 c3be 1a24 ddb0 2f13 7591  W..JY'...$../.u.
00000110: c8a3 fdbd 83a3 a6dc 7fd9 91fb 47ad d666  ............G..f
00000120: a53c 693a 08ce d4ac faf3 40eb 5114 5ff5  .<i:......@.Q._.
00000130: 3715 1bf2 b0d3 de6b 746a e5a2 d358 b744  7......ktj...X.D
00000140: 38e8 ab0b fdf6 34dd c175 8361 1265 e75d  8.....4..u.a.e.]
00000150: 3392 ae6f 4a95 daf2 9d3a 78a6 541e cb42  3..oJ....:x.T..B
00000160: 16fa 8707 59e8 5a69 1d46 036d f2a5 a9d0  ....Y.Zi.F.m....
00000170: cdd5 3474 7925 89de a8c1 8fc1 bf6a efbd  ..4ty%.......j..
00000180: d86d 1fcb e7cd e3cd ebfa 39f1 9b66 eae2  .m........9..f..
00000190: 3c8c dfc9 5805 a7bf 4e42 f1b6 98cc 98ba  <...X...NB......
000001a0: be29 956a 4b77 eae0 9952 71bc 6895 1cc7  .).jKw...Rq.h...
000001b0: b1c6 2a9b 846c 66b2 6461 2afc eb65 9fbb  ..*..lf.da*..e..
000001c0: a8a3 fe49 a04f a6d7 7473 d6ed 62e2 dc58  ...I.O..ts..b..X
000001d0: 2c3a 4f9c 59c3 be5a e92c 2b6c 2ccc 6fea  ,:O.Y..Z.,+l,.o.
000001e0: 65d9 642f bf3c b9c7 ed49 b2fa 571f 3300  e.d/.<...I..W.3.
000001f0: 0000 0000 70cf b217 fcec ff01 0000 0000  ....p...........
00000200: c835 f6ff 0000 0000 00e4 1fdf ff03 0000  .5..............
00000210: 0000 907f bcff 0700 0000 0020 ffd8 ff03  ........... ....
00000220: 0000 0000 907f 7cff 0f00 0000 0040 fef1  ......|......@..
00000230: fe1f 0000 0000 80fc 63ff 0f00 0000 0000  ........c.......
00000240: 0000 0000 0000 0000 0000 0000 0000 ffa6  ................
00000250: ef58 8985 d900 c800 00                   .X.......
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
