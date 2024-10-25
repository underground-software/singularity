#!/usr/bin/env python3
import sys

import utilities

assignment = sys.argv[1]

utilities.release_subs([sub for sub in
                        utilities.user_to_sub(assignment, 'final').values()
                        if sub])

print(f'final subs for {assignment} released')

utilities.update_tags(assignment, 'final')
