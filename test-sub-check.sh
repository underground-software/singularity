#!/usr/bin/env bash

set -exuo pipefail

source test-lib

setup_testdir

# login as bob
curl --url "https://$SINGULARITY_HOSTNAME/login" \
  --unix-socket ./socks/https.sock \
  "${CURL_OPTS[@]}" \
  -c test/cookies \
  --data "username=bob&password=builder" \
  | tee test/login_success \
  | grep "msg = bob authenticated by password"


# check for setup assignment and save dashboard
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  -b test/cookies \
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
  -c test/cookies_bab \
  --data "username=bab&password=builder" \
  | tee test/login_success_bab \
  | grep "msg = bab authenticated by password"


# check for setup assignment and save dashboard
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  -b test/cookies_bab \
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
  -c test/cookies_bib \
  --data "username=bib&password=builder" \
  | tee test/login_success_bib \
  | grep "msg = bib authenticated by password"


# check for setup assignment and save dashboard
curl --url "https://$SINGULARITY_HOSTNAME/dashboard" \
  --unix-socket ./socks/https.sock \
  -b test/cookies_bib \
  "${CURL_OPTS[@]}" \
  | tee test/dashboard_bib \
  | grep "setup"

grep "Total Score: 80.0" test/dashboard_bib

grep "bob Peer Review" test/dashboard_bib

grep "bab Peer Review" test/dashboard_bib

grep "patchset applies." test/dashboard_bib

grep 'Perfect. But no peer review!' test/dashboard_bib

echo "ALL SUBMISSION TESTS PASS"
