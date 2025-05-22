#!/usr/bin/env python3
import sys

import utilities

assignment = sys.argv[1]

usernames_to_subs = utilities.user_to_sub(assignment, 'final')

utilities.release_subs([sub.submission_id for sub in usernames_to_subs.values() if sub])

print(f'final subs for {assignment} released')

tags = utilities.update_tags(assignment, 'final')

utilities.run_automated_checks(tags, usernames_to_subs)
