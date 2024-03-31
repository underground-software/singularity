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
require "${DOCKER}"

# Check for shell script style compliance with shellcheck
./script-lint.sh

# Check python style compliance with flake8
pushd orbit
./test-style.sh
popd

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
00000000: 1f8b 0800 0000 0000 0003 edda 4d4f db30  ............MO.0
00000010: 18c0 f104 4adf a452 7a98 7242 f371 9510  ....J..Rz.rB.q..
00000020: 24a5 eb65 9a34 867a 40eb bad1 b507 4e55  $..e.4.z@.....NU
00000030: 503d 88a0 298b 5301 47f8 28fb 3ed3 0efb  P=..).S.G.(.>...
00000040: 323b cec9 30a2 4c6c 9db6 6a5a f4ff 4989  2;..0.Ll..jZ..I.
00000050: 9dc4 b1fc 3c71 0f96 3b89 0e83 7873 7468  ....<q..;...xsth
00000060: 2d90 abb5 9acd b4d4 664b cf4b eb5e b3e5  -.......fK.K.^..
00000070: 365a 0db7 d9dc b65c cf6d b5b6 2de1 2e72  6Z.....\.m..-..r
00000080: 50c6 54c5 7ea4 87f2 a7fd dc0f ee3f f16e  P.T.~........?.n
00000090: bf13 c452 bc9f 4463 3f16 dbd6 9a65 dbd6  ...R..Dc?....e..
000000a0: 0b21 f423 5b1f a53b 4d97 f591 bb73 6dcf  .!.#[..;M....sm.
000000b0: d1bd 6d6d 461f 2bd5 af56 b152 b3aa 4fab  ..mmF.+..V.R..O.
000000c0: 9f56 bd6a 6ef5 4ba5 b66a 553e ffc5 3000  .V.jn.K..jU>..0.
000000d0: 0000 00e0 f75d 3dcb 179c f575 fb7a 2ff6  .....]=....u.z/.
000000e0: 0f4f 6528 cfa7 4a46 ca94 85dd 5e7b a7df  .Oe(..JF....^{..
000000f0: 16fd 9d97 9db6 3077 c593 7229 9247 818a  ......0w..r).G..
00000100: 233f 0e26 e130 1889 208c e591 8cc4 5914  #?.&.0.. .....Y.
00000110: 8cfd e852 9cc8 cb8d 7249 c5d3 910c e3a4  ...R....rI......
00000120: 816e 1c84 4762 d0dd db1f b445 f74d 5f74  .n..Gb.....E.M_t
00000130: 079d 8e6e 9374 19fa 63f9 708b 335f a9f3  ...n.t..c.p.3_..
00000140: 4974 db87 7954 df2a e69d dd75 db0a c291  It..yT.*...u....
00000150: bc50 1f4e f5da 6ee8 4fe3 497a 3d34 c31d  .P.N..n.O.Iz=4..
00000160: 364c adb4 5598 eb05 cfd4 8a57 8f97 bfe7  6L..U......W....
00000170: a796 e647 49a5 74c0 ca94 b999 fc98 bb3a  ...GI.t........:
00000180: 3fe2 463c 3991 a119 f7db dede eb9d de81  ?.F<9...........
00000190: 78d5 3ed8 b86d f1cb f04d 4379 7116 e8c4  x.>..m...MCyq...
000001a0: fe90 8395 9f85 6486 346c 985a 7e2b 37d7  ......d.4l.Z~+7.
000001b0: 0b9e a9ad 5c3d b20b 8ee3 d8d7 a534 0769  ....\=.......4.i
000001c0: 62d2 d3d2 4cf4 b753 e3c1 d930 c797 3e1f  b...L..S...0..>.
000001d0: 1dfb eaf8 7e90 b333 e9a6 f37a 7d29 ef3c  ....~..3...z}).<
000001e0: 771e 0ae4 e64b a645 b296 2f26 d3bd 929c  w....K.E../&....
000001f0: d6fe e92f 0e00 0000 0000 2c58 3939 b1fe  .../......,X99..
00000200: 0700 0000 0020 d3d8 ff07 0000 0000 20fb  ..... ........ .
00000210: d8ff 0700 0000 0020 fb58 ff03 0000 0000  ....... .X......
00000220: 907d fcff 1f00 0000 0080 ec63 ff1f 0000  .}.........c....
00000230: 0000 80ec 63fd 0f00 0000 0000 0064 d737  ....c........d.7
00000240: bf0b 8b24 0096 0000                      ...$....
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
