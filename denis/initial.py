#!/usr/bin/env python3

import os
import random
import sys

import db
import mailman.db
import orbit.db

# this is passed from start.py via run-at
assignment = sys.argv[1]

students_who_submitted = [user.username for user in orbit.db.User.select()
                          if mailman.db.Submission.get_or_none((mailman.db.Submission.user == user.username) &  # NOQA: E501
                                                               (mailman.db.Submission.recipient == assignment)) is not None]  # NOQA: E501

# let them see emails that have been sent since last final due date
for student in students_who_submitted:
    os.system(f'restrict_access /var/lib/email/journal/journal -a {student}')


# We want peer review assignments where everyone gives two reviews
# and recieves two reviews i.e. a graph structure where each node has
# indeg and outdeg 2. There are many such graphs possible, but an easy
# option is to form review assignments from adjacent triplets in a
# cycle formed from all the names in a random order.

# put the names in a random order
random.shuffle(students_who_submitted)

# Grab adjacent triplets. We can use negative indices in python to easily
# get the wrapping around behavior we want for forming cycles. Edge case
# is the situation where there are fewer than 3 students total and it is
# impossible to have any triplets. In that case we can form two pairs,
# one singleton, or the empty list which is why we have min(len, 3)
reviews = [[students_who_submitted[i+j]
            for j in range(-min(len(students_who_submitted), 3), 0)]
           for i in range(len(students_who_submitted))]


try:
    with db.DB.atomic():
        db.PeerReviewAssignment.insert_many(
            [{'assignment': assignment,
              'reviewer': reviewer,
              'reviewee1': reviewees[0] if len(reviewees) >= 1 else None,
              'reviewee2': reviewees[1] if len(reviewees) >= 2 else None}
             for [reviewer, *reviewees] in reviews]).execute()
except db.peewee.IntegrityError as e:
    print(e)
