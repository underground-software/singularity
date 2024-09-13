#!/usr/bin/env python3

import collections
from pathlib import Path
import sys

import patchset
import db

ASSIGNMENT_LIST = ["introductions",
                   "exercise0", "exercise1", "exercise2",
                   "programming0", "programming1", "programming2",
                   "final0", "final1"]


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
    # isn't a patchset at all, but it could be a peer review.
    if cover_letter.rcpt not in ASSIGNMENT_LIST:
        if patches or user == cover_letter.rcpt:
            return 0
        with open(f'/var/lib/email/mail/{cover_letter.msg_id}', 'r') as f:
            for line in f:
                if line == '':
                    return 0
                if not line.startswith('In-Reply-To: '):
                    continue
                lt_ind = line.find('<')
                at_ind = line.find('@')
                if lt_ind == -1 or at_ind == -1 or lt_ind > at_ind:
                    return 0
                irt = line[lt_ind+1:at_ind]
                break
        # 'clear the lower 16 bits' to get the reviewee patchset id
        patchset_id = irt[:-4]+'0000'
        reviewee_sub = (db.Submission
                          .select()
                          .where(db.Submission.submission_id == patchset_id)
                          .first())
        db.PeerReview.create(review_id=logfile, reviewer=user,
                             reviewee=cover_letter.rcpt,
                             assignment=reviewee_sub.assignment,
                             timestamp=timestamp)
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
