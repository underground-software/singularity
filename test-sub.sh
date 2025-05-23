#!/bin/bash

set -exuo pipefail

SCRIPT_DIR=$(dirname $0)

cd $SCRIPT_DIR

get_git_port() { podman port singularity_git_1 | awk -F':' '{ print $2 }' ; } ;

# nuke grading repo inside container
podman-compose exec git ash -c 'cd /var/lib/git/grading.git && for t in $(git tag); do git tag -d $t; done'

# setup submissions repo
rm -rf repos/submissions
git/admin.sh submissions "course submissions repository"
pushd repos
git init --bare submissions
git init submissions_init
pushd submissions_init
echo "# submissions" > README.md
git add README.md
git -c user.name=singularity -c user.email=singularity@singularity commit -m 'init submissions repo'
git push ../submissions master
popd
rm -rf submissions_init
pushd submissions
git push --mirror http://localhost:$(get_git_port)/cgi-bin/git-receive-pack/submissions
popd
popd

# create bob,bib,bab users or change their passwords to builder
orbit/warpdrive.sh -u bob -p builder -n || orbit/warpdrive.sh -u bob -p builder -m
orbit/warpdrive.sh -u bib -p builder -n || orbit/warpdrive.sh -u bob -p builder -m
orbit/warpdrive.sh -u bab -p builder -n || orbit/warpdrive.sh -u bob -p builder -m

# create or recreate setup assignment
if denis/configure.sh dump | grep -q "^setup:"; then
	denis/configure.sh remove -a setup
fi
denis/configure.sh create -a setup -i $(date -d "15 secs" +%s) -p $(date -d "25 secs" +%s) -f $(date -d "30 secs" +%s)
denis/configure.sh reload

WORKDIR=$(mktemp -d)

# setup assignment environment
pushd $WORKDIR

mkdir certs
pushd certs
podman volume export singularity_ssl-certs > certs.tar
tar xf certs.tar
popd

git clone http://localhost:$(get_git_port)/submissions
mkdir submissions/bob
pushd submissions/bob
git config user.name bob
git config user.email bob@localhost.localdomain
git config sendemail.smtpUser bob
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
mkdir good corrupt whitespace nocover nocover-corrupt

# create patchsets

# good patchset
pushd good

echo "abc" > work
git add work
git commit -sm 'add abc to work'

echo "def" >> work
git add work
git commit -sm 'add def to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/Good patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/Good patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to setup@localhost.localdomain *.patch
popd

sleep 1

# corrupt patchset
pushd corrupt

echo "abc" > work
git add work
git commit -sm 'add abc to work'

echo "def" >> work
git add work
git commit -sm 'add def to work'

echo "ghi" >> work
git add work
git commit -sm 'add ghi to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/Corrupt patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/Corrupt patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to setup@localhost.localdomain *.patch
popd

sleep 1

# patchset with whitespace errors
pushd whitespace

echo "abc" > work
git add work
git commit -sm 'add abc to work'

echo "def	" >> work
git add work
git commit -sm 'add def to work'

echo "ghi	" >> work
git add work
git commit -sm 'add ghi to work'

git format-patch --rfc --cover-letter -v1 -3
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/Patchset with whitespace errors/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/Patchset with whitespace errors/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to setup@localhost.localdomain *.patch
popd

sleep 1

# patchset with no cover letter
pushd nocover

echo "abc" > work
git add work
git commit -sm 'add abc to work'

echo "def" >> work
git add work
git commit -sm 'add def to work'

git format-patch --rfc -v1 -2

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to setup@localhost.localdomain *.patch
popd

sleep 1

# patchset with no cover letter and corrupt first patch
pushd nocover-corrupt

echo "abc" > work
git add work
git commit -sm 'add abc to work'

echo "def" >> work
git add work
git commit -sm 'add def to work'

echo "ghi" >> work
git add work
git commit -sm 'add ghi to work'

git format-patch --rfc -v1 -2

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to setup@localhost.localdomain *.patch
popd

# end of patchset sending
popd

# bab initial submission
git clone http://localhost:$(get_git_port)/submissions bab_submissions
mkdir bab_submissions/bab
pushd bab_submissions/bab
git config user.name bab
git config user.email bab@localhost.localdomain
git config sendemail.smtpUser bab
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
mkdir bab_good

# bab good patchset
pushd bab_good

echo "abc" > work
git add work
git commit -sm 'bab: add abc to work'

echo "def" >> work
git add work
git commit -sm 'bab: add def to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/bab: Good patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/bab: Good patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to setup@localhost.localdomain *.patch
popd

# end of bab initial submission
popd

# bib initial submission
git clone http://localhost:$(get_git_port)/submissions bib_submissions
mkdir bib_submissions/bib
pushd bib_submissions/bib
git config user.name bib
git config user.email bib@localhost.localdomain
git config sendemail.smtpUser bib
git config sendemail.smtpPass builder
git config sendemail.smtpserver localhost.localdomain
git config sendemail.smtpserverport 465
git config sendemail.smtpencryption ssl
mkdir bib_good

# bib good patchset
pushd bib_good

echo "abc" > work
git add work
git commit -sm 'bib: add abc to work'

echo "def" >> work
git add work
git commit -sm 'bib: add def to work'

git format-patch --rfc --cover-letter -v1 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/bib: Good patchset/g' v1-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/bib: Good patchset/g' v1-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to setup@localhost.localdomain *.patch
popd

# end of bib initial submission
popd

sleep 1

# investigate grading repo
git clone http://localhost:$(get_git_port)/grading.git
pushd grading
git fetch --tag
git tag


STATUSES=(
'patchset applies.'
'patch 1 failed to apply!'
'whitespace error patch(es) 2,3?'
'missing cover letter!'
'missing cover letter and first patch failed to apply!'
'patchset applies.'
'patchset applies.')

# submitted patchses should have statuses in this order
# assumption: first ID tag is first patch submitted by this script and IDs increase monotonically
i=0
for t in $(git tag); do
	git show -s --oneline $t | grep -q "${STATUSES[$i]}"
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

# submit peer review 1
mkdir submissions/bob/peer1
pushd submissions/bob/peer1

cat <<PEER_REVIEW1 > review1
Subject: setup review 1 for bab
In-Reply-To: <${PEER1_ID::-1}1@localhost.localdomain>

Looks good to me

Acked-by: bob <bob@localhost.localdomain>
PEER_REVIEW1

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to bab@localhost.localdomain review1

# end peer review 1
popd

# submit peer review 2
mkdir submissions/bob/peer2
pushd submissions/bob/peer2

cat <<PEER_REVIEW2 > review2
Subject: setup review 2 for bib
In-Reply-To: <${PEER2_ID::-1}2@localhost.localdomain>

Looks good to me

Acked-by: bob <bob@localhost.localdomain>
PEER_REVIEW2

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to bib@localhost.localdomain review2

# end peer review 2
popd

sleep 1

# make final submission
pushd submissions/bob

# good final patchset
mkdir good-final
pushd good-final

echo "abc" > work
git add work
git commit -sm 'add abc to work'

echo "def" >> work
git add work
git commit -sm 'add def to work'

git format-patch --cover-letter -v2 -2
sed -i 's/\*\*\* SUBJECT HERE \*\*\*/Good patchset final/g' v2-0000-cover-letter.patch
sed -i 's/\*\*\* BLURB HERE \*\*\*/Good patchset final/g' v2-0000-cover-letter.patch

git send-email --confirm=never --smtp-ssl-cert-path=$WORKDIR/certs/fullchain.pem --to setup@localhost.localdomain *.patch
popd

# end final submission
popd

echo "wait for final submission deadline (10 secs)"
sleep 10

pushd grading
git fetch --tag
sleep 2
git fetch -f origin refs/notes/*:refs/notes/*
git remote set-url --push origin http://localhost:$(get_git_port)/cgi-bin/git-receive-pack/grading.git
git notes --ref=grade add setup_final_bob -m '66'
git notes --ref=grade add setup_review1_bob -m '22'
git notes --ref=grade add setup_review2_bob -m '99'
git push origin refs/notes/*:refs/notes/*

echo $WORKDIR
