#!/usr/bin/env python3
import sys

import utilities

assignment = sys.argv[1]

ids = []

ids += [sub.submission_id for sub in utilities.user_to_sub(assignment, 'review1').values() if sub]
ids += [sub.submission_id for sub in utilities.user_to_sub(assignment, 'review2').values() if sub]

utilities.release_subs(ids)

print(f'peer review subs for {assignment} released')

utilities.update_tags(assignment, 'review1')
utilities.update_tags(assignment, 'review2')
