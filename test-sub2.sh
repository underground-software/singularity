#!/bin/bash

# test a bunch of rubric violations

source test-lib

setup_submissions_and_grading_repo

cat << EOF > "$WORKDIR"/coding_rubric
[{('--- /dev/null', '+++ b/user/coding/program.c'): 0},
{('--- a/user/coding/program.c', '+++ b/user/coding/program.c'): 0},
{('--- /dev/null', '+++ b/user/coding/Makefile'): 0}]
EOF

create_lighting_assignment coding 25 28 30  "$WORKDIR"/coding_rubric

setup_submissions_for bob

enter_and_checkout coding_initial_bob_toomany
write_commit_to "C program" bob/coding/program.c
write_commit_to "More C program" bob/coding/program.c "append"
write_commit_to "Yet more C program" bob/coding/program.c "append"
write_commit_to "Makefile content" bob/coding/Makefile
git format-patch -v1 --cover-letter --rfc -4
fixup_cover "Too many patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_toofew
write_commit_to "C program" bob/coding/program.c
write_commit_to "Makefile content" bob/coding/Makefile
git format-patch -v1 --cover-letter --rfc -2
fixup_cover "Too few patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_top-level-first
write_commit_to "C program" program.c
write_commit_to "More C program" bob/coding/program.c "append"
write_commit_to "Makefile content" Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Top level first file patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_top-level-third
write_commit_to "C program" bob/coding/program.c
write_commit_to "More C program" bob/coding/program.c "append"
write_commit_to "Makefile content" Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Top level third file patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_second-level-first
write_commit_to "C program" bob/program.c
write_commit_to "More C program" bob/program.c "append"
write_commit_to "Makefile content" bob/coding/Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Second level first file patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_second-level-third
write_commit_to "C program" bob/coding/program.c
write_commit_to "More C program" bob/coding/program.c "append"
write_commit_to "Makefile content" bob/Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Second level third file patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_fourth-level-first
write_commit_to "C program" bob/coding/program/program.c
write_commit_to "More C program" bob/coding/program/program.c "append"
write_commit_to "Makefile content" bob/coding/Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Fourth level first file patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_fourth-level-third
write_commit_to "C program" bob/coding/program.c
write_commit_to "More C program" bob/coding/program.c "append"
write_commit_to "Makefile content" bob/coding/program/Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Fourth level third file patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_wrong-second-dir-first
write_commit_to "C program" bob/setup/program.c
write_commit_to "More C program" bob/setup/program.c "append"
write_commit_to "Makefile content" bob/coding/Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Wrong second directory first patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_wrong-second-dir-third
write_commit_to "C program" bob/coding/program.c
write_commit_to "More C program" bob/coding/program.c "append"
write_commit_to "Makefile content" bob/setup/Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Wrong second directory third patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_wrong-filename-first
write_commit_to "C program" bob/coding/hello.c
write_commit_to "More C program" bob/coding/hello.c "append"
write_commit_to "Makefile content" bob/coding/Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Wrong filename first patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_wrong-filename-third
write_commit_to "C program" bob/coding/program.c
write_commit_to "More C program" bob/coding/program.c "append"
write_commit_to "Makefile content" bob/coding/Snakefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Wrong filename third patches"
exit_after_sending coding

enter_and_checkout coding_initial_bob_good
write_commit_to "C program" bob/coding/program.c
write_commit_to "More C program" bob/coding/program.c "append"
write_commit_to "Makefile content" bob/coding/Makefile
git format-patch -v1 --cover-letter --rfc -3
fixup_cover "Good patches"
exit_after_sending coding

pushd "$WORKDIR"
git clone http://localhost:"$(get_git_port)"/grading.git
pushd grading

STATUSES=(
"patch count 4 violates expected rubric patch count of 3!"
"patch count 2 violates expected rubric patch count of 3!"
"illegal patch 1: permission denied for path program.c!"
"illegal patch 3: permission denied for path Makefile!"
"patch 1 violates the assignment rubric!"
"patch 3 violates the assignment rubric!"
"patch 1 violates the assignment rubric!"
"patch 3 violates the assignment rubric!"
"patch 1 violates the assignment rubric!"
"patch 3 violates the assignment rubric!"
"patch 1 violates the assignment rubric!"
"patch 3 violates the assignment rubric!"
"patchset applies."
)

# submitted patchses should have statuses in this order
# assumption: first ID tag is first patch submitted by this script and IDs increase monotonically
i=0
for t in $(git tag); do
	git show -s --oneline "$t" | grep -q "${STATUSES[$i]}"
	i=$((i+1))
done
popd
popd

echo "RUBRIC CHECKS PASS"
echo "$WORKDIR"
