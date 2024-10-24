#!/usr/bin/env python3

import argparse
import sys

import db
import orbit.db
import mailman.db


def update_tags(assignment=None, component=None, user=None):
    assignments = ([assignment] if assignment
                   else [a.name for a in db.Assignment.select()])
    components = ([component] if component
                  else ['initial', 'review1', 'review2', 'final'])
    users = ([user] if user
             else [u.username for u in orbit.db.User.select()])

    grd_tbl = mailman.db.Gradeable
    s0 = grd_tbl.select().order_by(-grd_tbl.timestamp)
    for asmt in assignments:
        s1 = s0.where(grd_tbl.assignment == asmt)
        for cmpt in components:
            s2 = s1.where(grd_tbl.component == cmpt)
            for usr in users:
                sub_entry = s2.where(grd_tbl.user == usr).first()
                tag_id = sub_entry.submission_id if sub_entry else None
                print(f'update tag called on {usr}\'s {cmpt} {asmt} '
                      f'submission with tag id {tag_id}')


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
