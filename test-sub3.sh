#!/bin/bash

# test total score calculation when assigned only 0 or 1 peer reviews legitimately

source test-lib

setup_submissions_and_grading_repo

# single peer review case

create_dummy_assignment first

setup_submissions_for bob

enter_and_checkout first_initial_bob_good
write_commit_to "abc" bob/first/work
write_commit_to "def" bob/first/work "append"
git format-patch --rfc --cover-letter -v1 -2
fixup_cover "Good patchset"
exit_after_sending first

setup_submissions_for bab

enter_and_checkout first_initial_bab_good
write_commit_to "abc" bab/first/work
write_commit_to "def" bab/first/work "append"
git format-patch --rfc --cover-letter -v1 -2
fixup_cover "Good patchset"
exit_after_sending first

trigger_deadline first initial

setup_submissions_for bob
enter_and_checkout first_final_bob_good
write_commit_to "abc" bob/first/work
write_commit_to "def" bob/first/work "append"
git format-patch --cover-letter -v2 -2
fixup_cover "Good final patchset"
exit_after_sending first

trigger_deadline first peer
trigger_deadline first final

# no peer review case

create_dummy_assignment second

setup_submissions_for bob

enter_and_checkout second_initial_bob_good
write_commit_to "abc" bob/second/work
write_commit_to "def" bob/second/work "append"
git format-patch --rfc --cover-letter -v1 -2
fixup_cover "Good patchset"
exit_after_sending second

trigger_deadline second initial

enter_and_checkout second_final_bob_good
write_commit_to "abc" bob/second/work
write_commit_to "def" bob/second/work "append"
git format-patch --cover-letter -v2 -2
fixup_cover "Good final patchset"
exit_after_sending second

trigger_deadline second peer
trigger_deadline second final

pushd "$WORKDIR"
git clone http://localhost:"$(get_git_port)"/grading.git
pushd grading

git fetch --tag
git fetch -f origin refs/notes/*:refs/notes/*
git remote set-url --push origin http://localhost:"$(get_git_port)"/cgi-bin/git-receive-pack/grading.git

# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=grade add first_final_bob -m '100'
# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=grade add first_review1_bob -fm '100'
# shellcheck disable=SC2086
git ${PINP_CONFIG} notes --ref=grade add second_final_bob -m '50'
# shellcheck disable=SC2086
git ${PINP_CONFIG} push origin refs/notes/*:refs/notes/*

popd
popd

# login as bob
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie-jar test/cookies \
  --data "username=bob&password=builder" \
  | tee test/login_success \
  | grep "msg = bob authenticated by password"


# get bob dashboard
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  --cookie test/cookies \
  "${CURL_OPTS[@]}" > test/dashboard

# first assginment should have full score since the single required peer review was completed perfectly
grep "Total Score: 100.0" test/dashboard
#  assginment should have half score since no peer review was needed and final sub got half score
grep "Total Score: 50.0" test/dashboard

echo "PEER REVIEW CORNER CASES PASS"
echo "$WORKDIR"
