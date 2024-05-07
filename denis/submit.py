#!/usr/bin/env python3

import db
from pathlib import Path
import sys

ASSIGNMENT_LIST = ["introductions",
                   "exercise0", "exercise1", "exercise2",
                   "programming0", "programming1", "programming2",
                   "final0", "final1"]


# We assume inputs are correct as a precondition
# Otherwise we simply crash
def main(argv):
    _, logdir, logfile = argv
    with open(Path(logdir) / logfile) as log:
        header, *email_lines = log.readlines()
    timestamp, user = header.split()
    emails = [line.split() for line in email_lines]
    recpts = {email[0] for email in emails}

    if len(recpts) != 1:
        return
    (to,) = recpts

    if to not in ASSIGNMENT_LIST:
        # TODO process peer review
        return 0

    # At this point, we know this is an assignment submission
    db.Submission.create(submission_id=logfile, assignment=to,
                         timestamp=timestamp, user=user, status="new")


if __name__ == "__main__":
    sys.exit(main(sys.argv))
