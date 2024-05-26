#!/usr/bin/env python3

import os
import sys

import denis.db
import orbit.db


# this is passed from start.py via run-at
assignment = sys.argv[1]

for user in orbit.db.User.select():
    sub = (denis.db.Submission
           .get_or_none((denis.db.Submission.user == user.username) &
                        (denis.db.Submission.assignment == assignment)))
    # let them see emails that have been sent since last final due date
    if sub is not None:
        os.system(f'restrict_access /var/lib/email/journal/journal -a {user.username}')
