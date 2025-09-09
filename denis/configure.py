#!/usr/bin/env python3

from datetime import datetime
from argparse import ArgumentParser as ap
from pathlib import Path
import os

import db


def main():
    parser = ap(prog='configure', description='Configure assignments')

    def add_assignment(parser, required=True):
        parser.add_argument('-a', '--assignment',
                            help='Assignment to operate on',
                            required=required)

    def add_initial(parser, required=True):
        parser.add_argument('-i', '--initial',
                            type=int,
                            help='Initial submission due date timestamp',
                            required=required)

    def add_peer_review(parser, required=True):
        parser.add_argument('-p', '--peer-review',
                            type=int,
                            help='Peer review submission due date timestamp',
                            required=required)

    def add_final(parser, required=True):
        parser.add_argument('-f', '--final',
                            type=int,
                            help='Final submission due date timetamp',
                            required=required)

    command_parsers = parser.add_subparsers(dest='command', required=True)

    create_parser = command_parsers.add_parser('create')
    add_assignment(create_parser)
    add_initial(create_parser)
    add_peer_review(create_parser)
    add_final(create_parser)

    alter_parser = command_parsers.add_parser('alter')
    add_assignment(alter_parser)
    add_initial(alter_parser, required=False)
    add_peer_review(alter_parser, required=False)
    add_final(alter_parser, required=False)

    remove_parser = command_parsers.add_parser('remove')
    add_assignment(remove_parser)

    dump_parser = command_parsers.add_parser('dump')
    dump_parser.add_argument('-i', '--iso',
                             action='store_true',
                             dest='fmt_iso',
                             help='Dump dates in ISO format')

    command_parsers.add_parser('reload')

    # Dictionary containing the desired command and all flags with their values
    kwargs = vars(parser.parse_args())
    # Subparsers store their name in the destination `'command'`
    subparser_name = kwargs.pop('command')
    # Get a handle to the function with the desired name
    subparser_func = globals()[subparser_name]
    # Call the desired subparser with the remaining flags/values as kwargs
    subparser_func(**kwargs)


def dirty():
    Path('/tmp/dirty').touch()


def create(assignment, initial, peer_review, final):
    try:
        db.Assignment.create(name=assignment,
                             initial_due_date=initial,
                             peer_review_due_date=peer_review,
                             final_due_date=final)
        dirty()
    except db.peewee.IntegrityError:
        print('cannot create assignment with duplicate name')


def alter(assignment, initial, peer_review, final):
    alterations = {}
    if initial is not None:
        alterations[db.Assignment.initial_due_date] = initial
    if peer_review is not None:
        alterations[db.Assignment.peer_review_due_date] = peer_review
    if final is not None:
        alterations[db.Assignment.final_due_date] = final
    if not alterations:
        return print('At least one new date must be specified')
    query = (db.Assignment
             .update(alterations)
             .where(db.Assignment.name == assignment))
    if query.execute() < 1:
        print(f'no such assignment {assignment}')
    else:
        dirty()


def remove(assignment):
    query = (db.Assignment
             .delete()
             .where(db.Assignment.name == assignment))
    if query.execute() < 1:
        print(f'no such assignment {assignment}')
    else:
        dirty()


def dump(fmt_iso):
    def timestamp_to_formatted(timestamp):
        dt = datetime.fromtimestamp(timestamp).astimezone()
        return dt.isoformat() if fmt_iso else dt.strftime('%a %b %d %Y %T %Z (%z)')

    if os.path.exists('/tmp/dirty'):
        print('WARNING: Denis database is dirty, reload to update waiters')

    print(' --- Assignments ---')
    for asn in db.Assignment.select():
        print(f'''{asn.name}:
\tInitial:\t{timestamp_to_formatted(asn.initial_due_date)}
\tPeer Review:\t{timestamp_to_formatted(asn.peer_review_due_date)}
\tFinal:\t\t{timestamp_to_formatted(asn.final_due_date)}''')


def reload():
    import os
    import signal
    os.kill(1, signal.SIGUSR1)
    if os.path.exists('/tmp/dirty'):
        os.remove('/tmp/dirty')


if __name__ == '__main__':
    exit(main())
