#!/bin/bash

# test only initial submission results in automatic 0

source test-lib

setup_submissions_and_grading_repo

create_dummy_assignment fun

setup_submissions_for bob

enter_and_checkout fun_initial_bob_only-initial
write_commit_to "C program" bob/fun/program.c
write_commit_to "More C program" bob/fun/program.c "append"
write_commit_to "Yet more C program" bob/fun/program.c "append"
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Only initial sub patchset"
exit_after_sending fun

trigger_deadline fun initial
trigger_deadline fun peer
trigger_deadline fun final

setup_testdir

# login as bob
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  --cookie-jar test/cookies \
  --data "username=bob&password=builder" \
  | tee test/login_success \
  | grep "msg = bob authenticated by password"


# check for fun assignment and save dashboard
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  --cookie test/cookies \
  "${CURL_OPTS[@]}" \
  | tee test/dashboard \
  | grep "fun"

grep "patchset applies." test/dashboard
grep "No submission" test/dashboard
grep "Total Score: 0.0" test/dashboard

echo "INITIAL SUBMISSION ONLY GETS AUTO ZERO CONFIRMED"
