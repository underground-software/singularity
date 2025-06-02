#!/usr/bin/env python3

import collections
from pathlib import Path
import sys

import db
import denis.db
import patchset


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
    timestamp = int(timestamp)

    emails = [email_from_log_line(line) for line in email_lines]

    # no emails in session, just logged in and didn't send anything
    if not emails:
        return 0

    sub = db.Submission(submission_id=logfile, timestamp=timestamp,
                        user=user, recipient=emails[0].rcpt,
                        email_count=len(emails))
    sub.save()

    irt_header = 'In-Reply-To: <'
    reply_id = None
    with open(f'/var/lib/email/mail/{emails[0].msg_id}') as f:
        for line in f:
            if not line:
                break
            if not line.startswith(irt_header):
                continue
            at_sign = line.find('@', len(irt_header))
            if -1 == at_sign:
                continue
            reply_email_id = line[len(irt_header):at_sign]

            # "clear the lower 16 bits" to get the reviewee patchset id
            reply_id = reply_email_id[:-4] + '0000'
            sub.in_reply_to = reply_id
            sub.save()
            break

    def set_status(status):
        sub.status = status
        sub.save()
        return 0

    asn_db = denis.db.Assignment
    gr_db = db.Gradeable
    if asn := asn_db.get_or_none(asn_db.name == emails[0].rcpt):
        cover_letter, *patches = emails
        auto_feedback = patchset.check(cover_letter, patches, logfile)
        if len(emails) < 2:
            return set_status('missing patches')
        typ = ('initial' if timestamp < asn.initial_due_date
               else 'final' if timestamp < asn.final_due_date else None)
        if not typ:
            return set_status(f'{asn.name} past due')
        gr_db.create(submission_id=logfile, timestamp=timestamp, user=user,
                     assignment=asn.name, component=typ, auto_feedback=auto_feedback)
        return set_status(f'{asn.name}: {typ}')

    if reply_id:
        auto_feedback = patchset.apply_peer_review(emails[0], logfile, reply_id)
        if not (orig := gr_db.get_or_none(gr_db.submission_id == reply_id)):
            return set_status('not a reply to a submission')
        asn_name = orig.assignment
        asn = asn_db.get_or_none(asn_name == asn_db.name)
        if not asn:
            raise RuntimeError('invalid assignment name in gradeable DB')
        if timestamp > asn.peer_review_due_date:
            return set_status(f'{asn.name} review past due')
        rev_db = denis.db.PeerReviewAssignment
        rev = rev_db.get_or_none((rev_db.assignment == asn_name) &
                                 (rev_db.reviewer == user))
        if not rev:
            return set_status('ineligible for peer review')
        match emails[0].rcpt:
            case rev.reviewee1:
                typ = 'review1'
            case rev.reviewee2:
                typ = 'review2'
            case _:
                return set_status('reviewed wrong submission')
        gr_db.create(submission_id=logfile, timestamp=timestamp,
                     user=user, assignment=asn_name, component=typ,
                     auto_feedback=auto_feedback)
        return set_status(f'{asn_name}: {typ}')

    return set_status('Not a recognized recipient')


if __name__ == "__main__":
    sys.exit(main(sys.argv))
