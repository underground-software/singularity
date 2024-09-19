#!/usr/bin/env python3

import collections
from pathlib import Path
import sys

import patchset
import db
import denis.db


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
    asn_db = denis.db.Assignment
    if not asn_db.get_or_none(asn_db.name == cover_letter.rcpt):
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

    sub.status = patchset.check(cover_letter, patches, submission_id=logfile)
    sub.save()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
