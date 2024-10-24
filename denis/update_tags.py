#!/usr/bin/env python3

import argparse
import sys


def update_tags(assignment=None, component=None, user=None):
    print(f'update tags for {component if component else "every component"} '
          f'of {user if user else "everone"}\'s '
          f'{assignment if assignment else "complete submission history"}')


if __name__ == '__main__':
    p = argparse.ArgumentParser(prog='update_tags',
                                description='Set/update git tags to mark the '
                                            'latest grade-worthy submissions '
                                            'in the grading git repo.')
    p.add_argument('-a', '--assignment',
                   help='Assignment to update. Update all if arg is not '
                        'provided.')
    p.add_argument('-c', '--component',
                   help='Initial/peer/final component of the specified '
                        'assignment. Update all if arg is not provided.')
    p.add_argument('-u', '--user',
                   help='User whose tags you wish to update. Update all if '
                   'arg is not provided.')
    args = p.parse_args(sys.argv[1:])

    update_tags(args.assignment, args.component, args.user)
