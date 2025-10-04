#!/usr/bin/env python3
import sys
import os

import utilities
import orbit.db

assignment = sys.argv[1]

usernames_to_subs = utilities.user_to_sub(assignment, 'final')

for oopsie in orbit.db.Oopsie.select().where(orbit.db.Oopsie.assignment == assignment):
    if usernames_to_subs[oopsie.user] is not None:
        os.system(f'restrict_access /var/lib/email/journal/journal -a {oopsie.user}')

utilities.release_subs([sub.submission_id for sub in usernames_to_subs.values() if sub])

tags = utilities.update_tags(assignment, 'final')

utilities.run_automated_checks(tags, usernames_to_subs)

print(f'completed {assignment} assignment processing for final submission deadline')
