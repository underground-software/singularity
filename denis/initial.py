#!/usr/bin/env python3

import io
import os
import pycurl
import random
import sys

import config
import db
import mailman.db
import orbit.db


def generate_peer_review_email(assignment, review_table):
    return f'''\
Subject: Peer review assignments for {assignment}

Hello everyone,

For peer review, find the row with your name in the left column
and review the patches submitted any others in that row:

 -- Begin Table --
{review_table}
 -- End Table --

Begin each review by creating a new branch based off the latest commit
to the master branch of upstream ILKD_submissions repository.

Your review must involve applying all the submitted patches in
sequential order and conducting the following tests:

- You must verify each patch applies cleanly

    - This means no corrupt or missing patches

- You must verify that no patch adds whitespace errors i.e.:

    - No whitespace at the end of any lines

    - No extra blank lines at the end of a file

    - Ensure there is a newline at the end of every file

- You must verify that the diffstat output right after the `---`
  in each patch seems reasonable, for example:

    - If this is patch 2/4, everything that the assignment directions
      specify to include in patch 2 is present and nothing else

    - If the directions say to put the files into a folder named after
      the assignment, all files added are in such a folder

    - If the directions say to add your code and a makefile, a file named
      `Makefile` and at least one file with the `.c` extension are added

    - No stray files unrelated to the assignment are included (e.g. code
      from other assignments or `.patch` files from previous attempts

- You must verify that the actual contents of the files
  added or modified by each patch are sane, for example:

    - If the patch adds code, the code should compile without
      errors/warnings and not immediately crash if you run it

    - If the patch adds the output of a command, is there anything
      actually in the file? Does it look like the kind of output
      one can expect from the command?

    - If the patch includes another patch, is it corrupt?

    - If the patch answers provided questions, is each one answered?

Refer to the particular assignment requirements for {assignment}
and the general submission procedures on the course website for details.

Document any issues you find in detail in your reply to the cover letter
of the submission.

Your reply should end with a trailer in the style of your "Signed-off-by:"
(DCO) line, either "Acked-by:" for approval or "Peer-reviewed-by:" if
any issues are encountered.

General Tips:

- Append this line to your `.muttrc` file to wire hitting the `l` key when
  in the mutt index to having mutt run `git am` in the directory where you
  invoked `mutt` and piping in the currently highlighted email patch

	macro index l '| git am'\\n

- This macro will not work when an email is open for viewing (unless you
  add another similar line that binds the key inside of the 'pager' menu
  instead of the 'index' menu)

- If patch application fails, subsequent use of this macro will fail since
  git is in a "running `git am`" state. You must abort this existing
  failed `git am` by running `git am --abort` in the repository.
  You can do that without needing to leave mutt by pressing `!` and
  entering `git am --abort` and pressing enter (The `!` shortcut
  also works for running any other shell command from within mutt).

- A cover letter has no diff so it is _not_ a patch! Don't try to apply it
    - An attempt to apply the cover letter will require a `git am --abort`
'''


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
              'reviewee1': reviewee1,
              'reviewee2': reviewee2}
             for (reviewer, reviewee1, reviewee2) in reviews]).execute()
except db.peewee.IntegrityError as e:
    print(e)

# To make it easier for the student to find their row, we can sort the
# list. This will alphabetize based on the first column (and only the
# first column because we know that each row has a unique value)
reviews.sort()


# To further regularize the output, we can sort the names of the peers
# within each row, keeping the student who will review in the first slot
# while we are at it, we can convert each row to a space separated string
review_rows = [' '.join([s, *sorted(p)]) for [s, *p] in reviews]

# Combine into final table
review_table = '\n'.join(review_rows)

email_contents = generate_peer_review_email(assignment, review_table)

client = pycurl.Curl()
client.setopt(client.URL, 'smtp://smtp:1465')

# Client must log in, so the server knows their username
# but the password is not verified by the upstream server,
# checking creds is handled by nginx, which we are bypassing
client.setopt(client.USERNAME, 'peer_review')
client.setopt(client.PASSWORD, 'password')

# The upstream server only supports auth plain sent with
# credentials immediately (immediate response form of sasl)
# cURL cannot detect whether an SMTP server supports that
# form of SASL auth (other protocols advertise whether it
# is supported), so it cURL defaults to the theoretically
# more compatible form where the type of authentication is
# sent followed by the actual credentials as a separate
# command. This form is not supported by our server so we
# need to tell cURL that it can and should go all at once.
client.setopt(client.SASL_IR, True)

client.setopt(client.MAIL_FROM, f'peer_review@{config.hostname}')
client.setopt(client.MAIL_RCPT, [f'peer_review@{config.hostname}'])

client.setopt(client.UPLOAD, True)
client.setopt(client.READFUNCTION, io.BytesIO(email_contents.encode()).read)

# If this throws, we can just crash
client.perform()
client.close()
print(f'Peer review for {assignment} sent')
