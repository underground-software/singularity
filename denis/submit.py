#!/usr/bin/env python3

import collections
from pathlib import Path
import sys
import git
import tempfile

import db

ASSIGNMENT_LIST = ["introductions",
                   "exercise0", "exercise1", "exercise2",
                   "programming0", "programming1", "programming2",
                   "final0", "final1"]

MAIL_DIR_ABSPATH = "/var/lib/email/mail"

REMOTE_URL = "http://host.containers.internal:3366/cgi-bin/git-receive-pack/grading.git"  # NOQA: E501


def try_or_false(do, exc):
    try:
        do()
        return True
    except exc as e:
        print(e, file=sys.stderr)
        return False


Email = collections.namedtuple('Email', ['rcpt', 'msg_id'])


def email_from_log_line(line):
    recipient, message_id = line.split()
    return Email(rcpt=recipient, msg_id=message_id)


# We assume inputs are correct as a precondition
# Otherwise we simply crash
def main(argv):
    _, logdir, logfile = argv
    with open(Path(logdir) / logfile) as log:
        header, *email_lines = log.readlines()
    timestamp, user = header.split()

    emails = [email_from_log_line(line) for line in email_lines]

    # no emails in session, just logged in and didn't send anything
    if not emails:
        return 0

    cover_letter, *patches = emails

    # if the 'cover letter' is not addressed to
    # an assignment inbox, this email session
    # isn't a patchset at all
    if cover_letter.rcpt not in ASSIGNMENT_LIST:
        # TODO process peer review
        return 0

    sub = db.Submission(submission_id=logfile, assignment=cover_letter.rcpt,
                        timestamp=timestamp, user=user, status='new')

    # only one email
    if not patches:
        # only one patch, but addressed to an
        # assignment inbox. This cannot be valid.
        sub.status = 'no patches or no cover letter'
        sub.save()
        return 0

    mis_addressed_patches = [str(i+1) for i, patch in enumerate(patches)
                             if patch.rcpt != cover_letter.rcpt]

    if mis_addressed_patches:
        sub.status = (f'patch(es) {",".join(mis_addressed_patches)} '
                      f'not addressed to {cover_letter.rcpt}')
        sub.save()
        return 0

    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.init(repo_path)
        maildir = Path(MAIL_DIR_ABSPATH)
        author_args = ["-c", "user.name=Denis", "-c",
                       "user.email=daemon@denis.d"]
        git_am_args = ["git", *author_args, "am", "--keep"]
        whitespace_errors = []
        for i, patch in enumerate(patches):
            patch_abspath = str(maildir / patch.msg_id)

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
            sub.status = f'patch {i+1} failed to apply'
            sub.save()
            return 0

        if whitespace_errors:
            sub.status = ('whitespace error patch(es) '
                          f'{",".join(whitespace_errors)}')
        else:
            sub.status = 'patchset applies'
        sub.save()

        repo.create_tag(logfile)
        repo.create_remote("origin", REMOTE_URL)
        repo.git.push("origin", tags=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
