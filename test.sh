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
00000010: 18c0 f104 4adf a4b6 f430 e584 e6e3 9010  ....J....0......
00000020: 4da0 c061 9ab4 0ef5 80d6 7583 b507 4e55  M..a......u...NU
00000030: 503d 88a0 098b 5301 c7f2 51f6 7da6 1df6  P=....S...Q.}...
00000040: 6576 5c12 7005 4cdd 3a6d 685a f4ff 49b1  ev\.p.L.:mhZ..I.
00000050: 9de4 8965 3f71 0f56 1a84 475e b43e 3c32  ...e?q.V..G^.><2
00000060: 1e91 1ddb 6e36 d3da 7950 db8e 9394 86d3  ....n6..yP......
00000070: dcb6 3737 eded 1ddb 316c c7de b19b 86b0  ..77....1l......
00000080: 1f73 50da 5845 6e18 0fe5 4ffb b16f 4ceb  .sP.XEn...O..oL.
00000090: ffc4 fbfd 8e17 49f1 2108 476e 2436 8d65  ......I.!.Gn$6.e
000000a0: c334 8d97 42c4 b7cc f828 dd09 5d8c 8fdc  .4..B....(..]...
000000b0: 9d73 738e ee4d 633d fc54 a97d 338a 95ba  .ss..Mc=.T.}3...
000000c0: 51db aa7d ae3a b55c f56b a55e 352a 5ffe  Q..}.:.\.k.^5*_.
000000d0: e234 0000 0000 e0f7 4d9e e70b d6ca 8a79  .4......M......y
000000e0: bd17 b947 67d2 9717 6325 43a5 ebc2 ee41  ...Gg...c%C....A
000000f0: bbd5 6b8b 5eeb 55a7 2df4 55f1 ac5c 0ae5  ..k.^.U.-.U..\..
00000100: b1a7 a2d0 8dbc c01f 7843 e1f9 913c 96a1  ........xC...<..
00000110: 380f bd91 1b5e 8953 79b5 562e a968 3c94  8....^.Sy.V..h<.
00000120: 7e94 04c4 c19e 7f2c fadd bdfd 7e5b 74df  ~......,....~[t.
00000130: f644 b7df e9c4 3149 97be 3b92 b323 ce5d  .D....1I..;..#.]
00000140: a52e 8270 da87 beb5 da28 e6ad dd15 d3f0  ...p.....(......
00000150: fca1 bc54 1fcf e2bd ddc0 1d47 417a 3ed0  ...T.......GAz>.
00000160: c31d 6ce8 56a9 5198 eb01 47b7 8a93 a78b  ..l.V.Q...G.....
00000170: 37f9 a9a7 f951 52a9 78c2 4ad7 b97b f9d1  7....QR.x.J..{..
00000180: 57e3 fc88 5b51 702a 7d3d ee77 077b 6f5a  W...[Qp*}=.w.{oZ
00000190: 0787 e275 fb70 6d1a f1cb e9eb 4079 79ee  ...u.pm.....@yy.
000001a0: c589 fd21 074b 3f9b 921e d260 43b7 f28d  ...!.K?....`C...
000001b0: dc5c 0f38 bab5 3479 6216 2ccb 32af 4b69  .\.8..4yb.,.2.Ki
000001c0: 0ed2 c4a4 c5c2 bdd9 4f97 c6cc d530 c79b  ........O....0..
000001d0: be18 9eb8 eae4 e124 efaf a4db ce57 5717  .......$.....WW.
000001e0: f2d6 0b6b d644 6edf 645a 257b f962 b2dc  ...k.Dn.dZ%{.b..
000001f0: 2b49 b1fc 4f7f 7100 0000 0000 e091 9593  +I..O.q.........
00000200: 82fd 3f00 0000 0000 99c6 f77f 0000 0000  ..?.............
00000210: 00b2 8fef ff00 0000 0000 641f fb7f 0000  ..........d.....
00000220: 0000 00b2 8fff ff03 0000 0000 907d 7cff  .............}|.
00000230: 0700 0000 0020 fbd8 ff03 0000 0000 0000  ..... ..........
00000240: d9f5 1df3 6b21 9400 9600 00              ....k!.....
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
