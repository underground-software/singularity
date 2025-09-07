#!/bin/bash

# test total score calculation when assigned only 0 or 1 peer reviews legitimately

source test-lib

setup_submissions_and_grading_repo

# single peer review case

cat << EOF > "$WORKDIR"/first_rubric
[{('--- /dev/null', '+++ b/bob/first/work'): 0},
{('--- a/bob/first/work', '+++ b/bob/first/work'): 0}]
EOF

create_lighting_assignment first 10 11 20

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

sleep 8

setup_submissions_for bob
enter_and_checkout first_final_bob_good
write_commit_to "abc" bob/first/work
write_commit_to "def" bob/first/work "append"
git format-patch --cover-letter -v2 -2
fixup_cover "Good final patchset"
exit_after_sending first

sleep 9

# no peer review case

cat << EOF > "$WORKDIR"/second_rubric
[{('--- /dev/null', '+++ b/bob/second/work'): 0},
{('--- a/bob/second/work', '+++ b/bob/second/work'): 0}]
EOF

create_lighting_assignment second 5 7 10

setup_submissions_for bob

enter_and_checkout second_initial_bob_good
write_commit_to "abc" bob/second/work
write_commit_to "def" bob/second/work "append"
git format-patch --rfc --cover-letter -v1 -2
fixup_cover "Good patchset"
exit_after_sending second

sleep 4

enter_and_checkout second_final_bob_good
write_commit_to "abc" bob/second/work
write_commit_to "def" bob/second/work "append"
git format-patch --cover-letter -v2 -2
fixup_cover "Good final patchset"
exit_after_sending second

sleep 4

pushd "$WORKDIR"
git clone http://localhost:"$(get_git_port)"/grading.git
pushd grading

git fetch --tag
sleep 2
git fetch -f origin refs/notes/*:refs/notes/*
git remote set-url --push origin http://localhost:"$(get_git_port)"/cgi-bin/git-receive-pack/grading.git

git notes --ref=grade add first_final_bob -m '100'
git notes --ref=grade add first_review1_bob -fm '100'
git notes --ref=grade add second_final_bob -m '50'
git push origin refs/notes/*:refs/notes/*

popd
popd

# login as bob
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  -c test/cookies \
  --data "username=bob&password=builder" \
  | tee test/login_success \
  | grep "msg = bob authenticated by password"


# get bob dashboard
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  -b test/cookies \
  "${CURL_OPTS[@]}" > test/dashboard

# first assginment should have full score since the single required peer review was completed perfectly
grep "Total Score: 100.0" test/dashboard
#  assginment should have half score since no peer review was needed and final sub got half score
grep "Total Score: 50.0" test/dashboard

echo "PEER REVIEW CORNER CASES PASS"
echo $WORKDIR
