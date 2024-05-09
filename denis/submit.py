#!/usr/bin/env python3

import db
from pathlib import Path
import sys
import git
import tempfile

ASSIGNMENT_LIST = ["introductions",
                   "exercise0", "exercise1", "exercise2",
                   "programming0", "programming1", "programming2",
                   "final0", "final1"]

MAIL_DIR_ABSPATH = "/mnt/email_data/mail"

REMOTE_URL = "http://host.containers.internal:3366/cgi-bin/git-receive-pack/grading.git"  # NOQA: E501


def try_or_false(do, exc):
    try:
        do()
        return True
    except exc as e:
        print(e, file=sys.stderr)
        return False


# We assume inputs are correct as a precondition
# Otherwise we simply crash
def main(argv):
    _, logdir, logfile = argv
    with open(Path(logdir) / logfile) as log:
        header, *email_lines = log.readlines()
    timestamp, user = header.split()
    emails = [line.split() for line in email_lines]
    recpts = {email[0] for email in emails}
    email_files = [email[1] for email in emails]

    if len(recpts) != 1:
        return
    (to,) = recpts

    if to not in ASSIGNMENT_LIST:
        # TODO process peer review
        return 0

    # At this point, we know this is an assignment submission
    sub = db.Submission.create(submission_id=logfile, assignment=to,
                               timestamp=timestamp, user=user, status="new")

    if len(email_files) < 2:
        sub.status = "no cover letter"
        sub.save()
        return 0

    coverletter_file, *patch_files = email_files
    # TODO process cover letter

    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.init(repo_path)
        maildir = Path(MAIL_DIR_ABSPATH)
        author_args = ["-c", "user.name=Denis", "-c",
                       "user.email=daemon@denis.d"]
        git_am_args = ["git", *author_args, "am"]
        whitespace_errors = []
        for i, patch_file in enumerate(patch_files):
            patch_abspath = str(maildir / patch_file)

            # Try and apply and fail if there are whitespace errors
            def do_git_am(extra_args=[]):
                repo.git.execute([*git_am_args, *extra_args, patch_abspath]),

            # If this fails, the patch may apply with whitespace errors
            if try_or_false(lambda: do_git_am(['--whitespace=error-all']),
                            git.GitCommandError):
                continue

            repo.git.execute(["git", *author_args, "am", "--abort"])

            # Try again, if we succeed, count this patch as a whitespace error
            if try_or_false(lambda: do_git_am(), git.GitCommandError):
                whitespace_errors.append(str(i+1))
                continue

            # If we still fail, the patch does not apply
            sub.status = f'patch #{i+1} failed to apply'
            sub.save()
            return 0

        if whitespace_errors:
            sub.status = f'whitespace error patche(s) {",".join(whitespace_errors)}'  # NOQA: E501
        else:
            sub.status = 'patchset applies'
        sub.save()

        repo.create_tag(logfile)
        repo.create_remote("origin", REMOTE_URL)
        repo.git.push("origin", tags=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
