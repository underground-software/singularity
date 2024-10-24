#!/usr/bin/env python3
import sys

import update_tags
import utilities

assignment = sys.argv[1]

utilities.release_subs([sub for sub in
                        utilities.user_to_sub(assignment, 'final').values()
                        if sub])

print(f'final subs for {assignment} released')

update_tags.update_tags(assignment, 'final')
