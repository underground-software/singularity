#!/bin/bash

# assumes singularity is running when invoked
# script is written to be as idempotent as posible

source test-lib

setup_submissions_and_grading_repo

create_dummy_assignment setup

# setup_intial_bob patchsets
setup_submissions_for bob

# good patchset
enter_and_checkout setup_initial_bob_good
write_commit_to "abc" bob/setup/work
write_commit_to "def" bob/setup/work "append"
git format-patch --rfc --cover-letter -v1 -2
fixup_cover "Good patchset"
exit_after_sending setup

# corrupt patchset
enter_and_checkout setup_initial_bob_corrupt
write_commit_to "abc" bob/setup/work
write_commit_to "def" bob/setup/work "append"
write_commit_to "ghi" bob/setup/work "append"
git format-patch --rfc --cover-letter -v2 -3
rm ./*-0002-*.patch
fixup_cover "Corrupt patchset"
exit_after_sending setup

# patchset with whitespace errors
enter_and_checkout setup_initial_bob_whitespace
write_commit_to "abc" bob/setup/work
write_commit_to "def	" bob/setup/work "append"
git format-patch --rfc --cover-letter -v3 -2
fixup_cover "Patchset with whitespace errors"
exit_after_sending setup

# patchset with no cover letter
enter_and_checkout setup_initial_bob_nocover
write_commit_to "abc" bob/setup/work
write_commit_to "def" bob/setup/work "append"
git format-patch --rfc -v4 -2
exit_after_sending setup

# patchset with no cover letter and corrupt first patch
enter_and_checkout setup_initial_bob_nocover-corrupt
write_commit_to "abc" bob/setup/work
write_commit_to "def" bob/setup/work "append"
write_commit_to "ghi" bob/setup/work "append"
git format-patch --rfc -v5 -2
exit_after_sending setup

# setup_initial_bab submissions
setup_submissions_for bab

# bab good patchset
enter_and_checkout setup_initial_bab_good
write_commit_to "abc" bab/setup/work
write_commit_to "def" bab/setup/work "append"
git format-patch --rfc --cover-letter -v1 -2
fixup_cover "Good patchset"
exit_after_sending setup

# setup_initial_bib submissions
setup_submissions_for bib

# bib good patchset
enter_and_checkout setup_initial_bib_good
write_commit_to "abc" bib/setup/work
write_commit_to "def" bib/setup/work "append"
git format-patch --rfc --cover-letter -v1 -2
fixup_cover "Good patchset"
exit_after_sending setup

# investigate grading repo
pushd "$WORKDIR"
git clone http://localhost:"$(get_git_port)"/grading.git
pushd grading
git fetch --tag

STATUSES=(
'patchset applies.'
'patch 2 failed to apply!'
'whitespace error patch 2?'
'missing cover letter!'
'missing cover letter and first patch failed to apply!'
'patchset applies.'
'patchset applies.')

# submitted patchses should have statuses in this order
# assumption: first ID tag is first patch submitted by this script and IDs increase monotonically
i=0
for t in $(git tag); do
	git show -s --oneline "$t" | grep -q "${STATUSES[$i]}"
	if [[ $i == 5 ]]; then
		PEER1_ID=$t
	elif [[ $i == 6 ]]; then
		PEER2_ID=$t
	fi
	i=$((i+1))
done
popd

trigger_deadline setup initial

setup_submissions_for bob

# setup bob peer review
enter_and_checkout setup_reviews_bob

# submit peer review 1
cat <<PEER_REVIEW1 > review1
Subject: setup review 1 for bab
In-Reply-To: <${PEER1_ID::-1}1@localhost.localdomain>

Looks good to me

Acked-by: bob <bob@localhost.localdomain>
PEER_REVIEW1
git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to bab@localhost.localdomain review1
rm review1

# submit peer review 2
cat <<PEER_REVIEW2 > review2
Subject: setup review 2 for bib
In-Reply-To: <${PEER2_ID::-1}2@localhost.localdomain>

Looks good to me

Acked-by: bob <bob@localhost.localdomain>
PEER_REVIEW2
git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to bib@localhost.localdomain review2
rm review2

popd
# end bob peer review
#trigger_deadline setup peer_review
trigger_deadline setup peer

# setup_final_bob good patchset
setup_submissions_for bob
enter_and_checkout setup_final_bob_good
write_commit_to "abc" bob/setup/work
write_commit_to "def" bob/setup/work "append"
git format-patch --cover-letter -v6 -2
fixup_cover "Good final patchset"
exit_after_sending setup

# setup_final_bib final submission incorrectly labeled RFC
setup_submissions_for bib
enter_and_checkout setup_final_bib_rfc
write_commit_to "abc" bib/setup/work
write_commit_to "def" bib/setup/work "append"
git format-patch --rfc --cover-letter -v1 -2
fixup_cover "RFC tagged final patchset"
exit_after_sending setup

# setup_final_bab submission in wrong directory
setup_submissions_for bab
enter_and_checkout setup_final_bab_illegal
write_commit_to "abc" work
write_commit_to "def" work "append"
git format-patch --rfc --cover-letter -v1 -2
fixup_cover "Illegal patchset"
exit_after_sending setup

trigger_deadline setup final

pushd grading
git fetch --tag
sleep 1
git fetch -f origin refs/notes/*:refs/notes/*
git remote set-url --push origin http://localhost:"$(get_git_port)"/cgi-bin/git-receive-pack/grading.git

# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=grade add setup_final_bob -m '66'
# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=grade add setup_review1_bob -m '22'
# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=grade add setup_review2_bob -m '99'
# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=feedback add setup_final_bob -m 'Good effort but try harder next time.'

# automatic 0 for peer reviews
# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=grade add setup_final_bib -m '100'
# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=feedback add setup_final_bib -m 'Perfect. But no peer review!'

# automatic 0 for peer reviews and final submission
# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=feedback add setup_final_bab -m 'Please review git'

git push origin refs/notes/*:refs/notes/*

echo "$WORKDIR"

popd
popd

setup_testdir

# login as bob
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie-jar test/cookies \
  --data "username=bob&password=builder" \
  | tee test/login_success \
  | grep "msg = bob authenticated by password"


# check for setup assignment and save dashboard
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  --cookie test/cookies \
  "${CURL_OPTS[@]}" \
  | tee test/dashboard \
  | grep "setup"

grep "Total Score: 64.9" test/dashboard

grep "missing cover letter and first patch failed to apply!" test/dashboard

grep "bib Peer Review" test/dashboard

grep "bab Peer Review" test/dashboard

grep "patchset applies." test/dashboard

grep "Good effort but try harder next time." test/dashboard

# login as bab
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie-jar test/cookies_bab \
  --data "username=bab&password=builder" \
  | tee test/login_success_bab \
  | grep "msg = bab authenticated by password"


# check for setup assignment and save dashboard
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  --cookie test/cookies_bab \
  "${CURL_OPTS[@]}" \
  | tee test/dashboard_bab \
  | grep "setup"

grep "Total Score: 0.0" test/dashboard_bab

grep "bib Peer Review" test/dashboard_bab

grep "bob Peer Review" test/dashboard_bab

grep "patchset applies." test/dashboard_bab

grep "illegal patch 1: permission denied for path work!" test/dashboard_bab

grep 'Please review git' test/dashboard_bab

# login as bib
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie-jar test/cookies_bib \
  --data "username=bib&password=builder" \
  | tee test/login_success_bib \
  | grep "msg = bib authenticated by password"


# check for setup assignment and save dashboard
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  --cookie test/cookies_bib \
  "${CURL_OPTS[@]}" \
  | tee test/dashboard_bib \
  | grep "setup"

grep "Total Score: 80.0" test/dashboard_bib

grep "bob Peer Review" test/dashboard_bib

grep "bab Peer Review" test/dashboard_bib

grep "patchset applies." test/dashboard_bib

grep 'Perfect. But no peer review!' test/dashboard_bib

echo "ALL SUBMISSION TESTS PASS"
