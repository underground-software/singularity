#!/usr/bin/env python3
import sys

import utilities

assignment = sys.argv[1]

ids = []

ids += [sub for sub in utilities.user_to_sub(assignment, 'review1').values() if sub]  # NOQA: E501
ids += [sub for sub in utilities.user_to_sub(assignment, 'review2').values() if sub]  # NOQA: E501

utilities.release_subs(ids)

print(f'peer review subs for {assignment} released')
