#!/usr/bin/env python3
import sys

import utilities

assignment = sys.argv[1]

ids = []

usernames_to_subs_review1 = utilities.user_to_sub(assignment, 'review1')
usernames_to_subs_review2 = utilities.user_to_sub(assignment, 'review2')

ids += [sub.submission_id for sub in usernames_to_subs_review1.values() if sub]
ids += [sub.submission_id for sub in usernames_to_subs_review2.values() if sub]

utilities.release_subs(ids)

tags1 = utilities.update_tags(assignment, 'review1')
tags2 = utilities.update_tags(assignment, 'review2')

utilities.run_automated_checks(tags1 + tags2, usernames_to_subs_review1 | usernames_to_subs_review2, peer=True)

print(f'completed {assignment} assignment processing for peer review submission deadline')
