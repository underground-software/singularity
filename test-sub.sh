#!/bin/bash

set -exuo pipefail

SCRIPT_DIR=$(dirname "$0")

cd "$SCRIPT_DIR"

get_git_port() { podman port singularity_git_1 | awk -F':' '{ print $2 }' ; } ;

# nuke grading repo inside container
# shellcheck disable=SC2016
podman-compose exec git ash -c 'cd /var/lib/git/grading.git && for t in $(git tag); do git tag -d $t; done'

# setup submissions repo
rm -rf repos/submissions
git/admin.sh submissions "course submissions repository"
pushd repos
git init --bare submissions
echo "course submissions repository" > submissions/description
git init submissions_init
pushd submissions_init
echo "# submissions" > README.md
git add README.md
git -c user.name=singularity -c user.email=singularity@singularity commit -m 'init submissions repo'
git push ../submissions master
popd
rm -rf submissions_init
pushd submissions
git push --mirror http://localhost:"$(get_git_port)"/cgi-bin/git-receive-pack/submissions
popd
popd

# create bob,bib,bab users or change their passwords to builder
orbit/warpdrive.sh -u bob -p builder -n || orbit/warpdrive.sh -u bob -p builder -m
orbit/warpdrive.sh -u bib -p builder -n || orbit/warpdrive.sh -u bob -p builder -m
orbit/warpdrive.sh -u bab -p builder -n || orbit/warpdrive.sh -u bob -p builder -m

WORKDIR=$(mktemp -d)

cat << EOF > "$WORKDIR"/setup_rubric
[{('--- /dev/null', '+++ b/bob/setup/work'): 0},
{('--- a/bob/setup/work', '+++ b/bob/setup/work'): 0}]
EOF

# create or recreate setup assignment
if denis/configure.sh dump | grep -q "^setup:"; then
	denis/configure.sh remove -a setup
fi
denis/configure.sh create -a setup -i "$(date -d "15 secs" +%s)" -p "$(date -d "25 secs" +%s)" -f "$(date -d "30 secs" +%s)" -r "$WORKDIR"/setup_rubric
denis/configure.sh reload

# setup assignment environment
pushd "$WORKDIR"

mkdir certs
pushd certs
podman volume export singularity_ssl-certs > certs.tar
tar xf certs.tar
popd
git clone http://localhost:"$(get_git_port)"/submissions

# bob env setup

pushd submissions
git config user.name bob
git config user.email bob@localhost.localdomain
git config sendemail.smtpUser bob
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
popd

# setup_intial_bob patchsets

# good patchset
pushd submissions
git checkout --orphan setup_initial_bob_good
git rm -rf ./*
mkdir -p bob/setup

echo "abc" > bob/setup/work
git add bob/setup/work
git commit -sm 'add abc to work'

echo "def" >> bob/setup/work
git add bob/setup/work
git commit -sm 'add def to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/Good patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/Good patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm ./*.patch
popd
sleep 1

# corrupt patchset
pushd submissions
git checkout --orphan setup_initial_bob_corrupt
git rm -rf ./*
mkdir -p bob/setup

echo "abc" > bob/setup/work
git add bob/setup/work
git commit -sm 'add abc to work'

echo "def" >> bob/setup/work
git add bob/setup/work
git commit -sm 'add def to work'

echo "ghi" >> bob/setup/work
git add bob/setup/work
git commit -sm 'add ghi to work'

git format-patch --rfc --cover-letter -v1 -3
rm ./*-0002-*.patch

sed -i 's/\*\*\* SUBJECT HERE \*\*\*/Corrupt patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/Corrupt patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm ./*.patch
popd
sleep 1

# patchset with whitespace errors
pushd submissions
git checkout --orphan setup_initial_bob_whitespace
git rm -rf ./*
mkdir -p bob/setup

echo "abc" > bob/setup/work
git add bob/setup/work
git commit -sm 'add abc to work'

echo "def	" >> bob/setup/work
git add bob/setup/work
git commit -sm 'add def to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/Patchset with whitespace errors/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/Patchset with whitespace errors/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm ./*.patch
popd
sleep 1

# patchset with no cover letter
pushd submissions
git checkout --orphan setup_initial_bob_nocover
git rm -rf ./*
mkdir -p bob/setup

echo "abc" > bob/setup/work
git add bob/setup/work
git commit -sm 'add abc to work'

echo "def" >> bob/setup/work
git add bob/setup/work
git commit -sm 'add def to work'

git format-patch --rfc -v1 -2

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm ./*.patch
popd
sleep 1

# patchset with no cover letter and corrupt first patch
pushd submissions
git checkout --orphan setup_initial_bob_nocover-corrupt
git rm -rf ./*
mkdir -p bob/setup

echo "abc" > bob/setup/work
git add bob/setup/work
git commit -sm 'add abc to work'

echo "def" >> bob/setup/work
git add bob/setup/work
git commit -sm 'add def to work'

echo "ghi" >> bob/setup/work
git add bob/setup/work
git commit -sm 'add ghi to work'

git format-patch --rfc -v1 -2

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm ./*.patch
popd

# end of setup_initial_bob patchsets

# bab env setup

pushd submissions
git config user.name bab
git config user.email bab@localhost.localdomain
git config sendemail.smtpUser bab
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
popd

# setup_initial_bab submissions

# bab good patchset
pushd submissions
git checkout --orphan setup_initial_bab_good
git rm -rf ./*
mkdir -p bab/setup

echo "abc" > bab/setup/work
git add bab/setup/work
git commit -sm 'add abc to work'

echo "def" >> bab/setup/work
git add bab/setup/work
git commit -sm 'add def to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/bab: Good patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/bab: Good patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm -rf ./*.patch
popd

# end of bab initial submission

# bib env setup
pushd submissions
git config user.name bib
git config user.email bib@localhost.localdomain
git config sendemail.smtpUser bib
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
popd

# bib initial submissions

# bib good patchset
pushd submissions
git checkout --orphan setup_initial_bib_good
git rm -rf ./*
mkdir -p bib/setup

echo "abc" > bib/setup/work
git add bib/setup/work
git commit -sm 'add abc to work'

echo "def" >> bib/setup/work
git add bib/setup/work
git commit -sm 'add def to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/bib: Good patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/bib: Good patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm ./*.patch
popd
sleep 1

# end of bib initial submission

# investigate grading repo
git clone http://localhost:"$(get_git_port)"/grading.git
pushd grading
git fetch --tag
git tag


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

echo "wait for initial submission deadline (10 secs)"
sleep 10

# bob env setup

pushd submissions
git config user.name bob
git config user.email bob@localhost.localdomain
git config sendemail.smtpUser bob
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
popd


# setup bob peer review
pushd submissions
git checkout --orphan setup_reviews_bob
git rm -rf ./*
# mkdir -p bob/setup (must be able to omit if missing)
echo ORPHAN > ORPHAN
git add ORPHAN
git commit -m 'orphan base'

# submit peer review 1

cat <<PEER_REVIEW1 > review1
Subject: setup review 1 for bab
In-Reply-To: <${PEER1_ID::-1}1@localhost.localdomain>

Looks good to me

Acked-by: bob <bob@localhost.localdomain>
PEER_REVIEW1

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to bab@localhost.localdomain review1
rm review1

# end peer review 1

# submit peer review 2

cat <<PEER_REVIEW2 > review2
Subject: setup review 2 for bib
In-Reply-To: <${PEER2_ID::-1}2@localhost.localdomain>

Looks good to me

Acked-by: bob <bob@localhost.localdomain>
PEER_REVIEW2

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to bib@localhost.localdomain review2
rm review2

# end peer review 2

# end bob peer review
popd
sleep 1

# bob env setup

pushd submissions
git config user.name bob
git config user.email bob@localhost.localdomain
git config sendemail.smtpUser bob
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
popd

# bob make final submission

# good final patchset
pushd submissions
git checkout --orphan setup_final_bob_good
git rm -rf ./*
mkdir -p bob/setup

echo "abc" > bob/setup/work
git add bob/setup/work
git commit -sm 'add abc to work'

echo "def" >> bob/setup/work
git add bob/setup/work
git commit -sm 'add def to work'

git format-patch --cover-letter -v2 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/Good patchset final/g' v2-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/Good patchset final/g' v2-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm ./*.patch
popd
sleep 1

# end bob final submission

# bib env setup

pushd submissions
git config user.name bib
git config user.email bib@localhost.localdomain
git config sendemail.smtpUser bib
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
popd

# bib final submission labeled RFC
pushd submissions
git checkout --orphan setup_final_bib_rfc
git rm -rf ./*
mkdir -p bib/setup

echo "abc" > bib/setup/work
git add bib/setup/work
git commit -sm 'add abc to work'

echo "def" >> bib/setup/work
git add bib/setup/work
git commit -sm 'add def to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/bib: RFC patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/bib: RFC patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm ./*.patch
popd
sleep 1

# end of bib final submission labeled RFC


# bab env setup

pushd submissions
git config user.name bab
git config user.email bab@localhost.localdomain
git config sendemail.smtpUser bab
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
popd


# bab final submission in wrong directory
pushd submissions
git checkout --orphan setup_final_bab_illegal
git rm -rf ./*
mkdir -p bib/setup

echo "abc" > work
git add work
git commit -sm 'add abc to work'

echo "def" >> work
git add work
git commit -sm 'add def to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/bab: Illegal patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/bab: Illegal patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path="$WORKDIR"/certs/fullchain.pem --to setup@localhost.localdomain ./*.patch
rm ./*.patch
popd
sleep 1

# end of bab final submission in wrong directory


echo "wait for final submission deadline (10 secs)"
sleep 10

pushd grading
git fetch --tag
sleep 2
git fetch -f origin refs/notes/*:refs/notes/*
git remote set-url --push origin http://localhost:"$(get_git_port)"/cgi-bin/git-receive-pack/grading.git
git notes --ref=grade add setup_final_bob -m '66'
git notes --ref=grade add setup_review1_bob -m '22'
git notes --ref=grade add setup_review2_bob -m '99'
git notes --ref=feedback add setup_final_bob -m 'Good effort but try harder next time.'

git notes --ref=grade add setup_final_bib -m '100'
git notes --ref=feedback add setup_final_bib -m 'Perfect. But no peer review!'

git notes --ref=feedback add setup_final_bab -m 'Please review git'

git push origin refs/notes/*:refs/notes/*

echo "$WORKDIR"
