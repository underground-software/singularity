#!/usr/bin/env python3

import collections
from pathlib import Path
import sys

import db


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
            break

    sub = db.Submission(submission_id=logfile, timestamp=timestamp,
                        user=user, recipient=emails[0].rcpt,
                        email_count=len(emails), in_reply_to=reply_id)

    def set_status(status):
        sub.status = status
        sub.save()
        return 0

    return set_status('Not a recognized recipient')


if __name__ == "__main__":
    sys.exit(main(sys.argv))
