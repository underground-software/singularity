#!/usr/bin/env python3

from datetime import datetime
from argparse import ArgumentParser as ap

import db
import orbit.db


def main():
    parser = ap(prog='inspector', description='Inspect submissions')

    command_parsers = parser.add_subparsers(dest='command', required=True,
                                            description='Action to take')

    submissions_parser = command_parsers.add_parser('submissions')
    submissions_parser.add_argument('-a', '--assignment',
                                    help='Restrict results by assignment',
                                    required=False)
    submissions_parser.add_argument('-u', '--username',
                                    help='Restrict results by username',
                                    required=False)

    gradables_parser = command_parsers.add_parser('gradables')
    gradables_parser.add_argument('-a', '--assignment',
                                  help='Restrict results by assignment',
                                  required=False)
    gradables_parser.add_argument('-u', '--username',
                                  help='Restrict results by username',
                                  required=False)
    gradables_parser.add_argument('-c', '--component',
                                  help='Restrict results by component',
                                  required=False)

    missing_parser = command_parsers.add_parser('missing')
    missing_parser.add_argument('-a', '--assignment',
                                help='Select the assignment',
                                required=True)

    oopsie_parser = command_parsers.add_parser('oopsie')
    oopsie_parser.add_argument('-a', '--assignment',
                               help='Check Oopsies used for a particular assignment',
                               required=False)
    oopsie_parser.add_argument('-u', '--username',
                               help='Check if a student used an Oopsie',
                               required=False)

    # Dictionary containing the desired command and all flags with their values
    kwargs = vars(parser.parse_args())
    # Subparsers store their name in the destination `'command'`
    subparser_name = kwargs.pop('command')
    # Get a handle to the function with the desired name
    subparser_func = globals()[subparser_name]
    # Call the desired subparser with the remaining flags/values as kwargs
    subparser_func(**kwargs)


def submissions(assignment, username):
    query = db.Submission.select().order_by(-db.Submission.timestamp)
    if assignment:
        query = query.where(db.Submission.recipient == assignment)
    if username:
        query = query.where(db.Submission.user == username)
    for sub in query:
        print(sub.submission_id,
              datetime.fromtimestamp(sub.timestamp).astimezone().isoformat(),
              sub.recipient, sub.user, sub.status)


def gradables(assignment, username, component):
    query = db.Gradeable.select().order_by(-db.Gradeable.timestamp)
    if assignment:
        query = query.where(db.Gradeable.assignment == assignment)
    if username:
        query = query.where(db.Gradeable.user == username)
    if component:
        query = query.where(db.Gradeable.component == component)
    for gbl in query:
        print(gbl.submission_id,
              datetime.fromtimestamp(gbl.timestamp).astimezone().isoformat(),
              gbl.assignment, gbl.user, gbl.component, gbl.status)


def missing(assignment):
    query = db.Submission.select().where(db.Submission.recipient == assignment)
    submitted = {sub.user for sub in query}
    for user in orbit.db.User.select():
        if user.username not in submitted:
            print(user.username)


def oopsie(assignment, username):
    query = orbit.db.Oopsie.select()
    if assignment:
        query = query.where(orbit.db.Oopsie.assignment == assignment)
    if username:
        query = query.where(orbit.db.Oopsie.user == username)
    for oopsie in query:
        print(datetime.fromtimestamp(oopsie.timestamp).astimezone().isoformat(),
              oopsie.assignment, oopsie.user)


if __name__ == '__main__':
    main()
