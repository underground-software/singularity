#!/usr/bin/env python3

from argparse import ArgumentParser as ap

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

    def add_final(parser, required=True):
        parser.add_argument('-f', '--final',
                            type=int,
                            help='Final submission due date timetamp',
                            required=required)

    command_parsers = parser.add_subparsers(dest='command', required=True)

    create_parser = command_parsers.add_parser('create')
    add_assignment(create_parser)
    add_initial(create_parser)
    add_final(create_parser)

    alter_parser = command_parsers.add_parser('alter')
    add_assignment(alter_parser)
    add_initial(alter_parser, required=False)
    add_final(alter_parser, required=False)

    remove_parser = command_parsers.add_parser('remove')
    add_assignment(remove_parser)

    command_parsers.add_parser('dump')
    command_parsers.add_parser('reload')

    # Dictionary containing the desired command and all flags with their values
    kwargs = vars(parser.parse_args())
    # Subparsers store their name in the destination `'command'`
    subparser_name = kwargs.pop('command')
    # Get a handle to the function with the desired name
    subparser_func = globals()[subparser_name]
    # Call the desired subparser with the remaining flags/values as kwargs
    subparser_func(**kwargs)


def create(assignment, initial, final):
    try:
        db.Assignment.create(name=assignment,
                             initial_due_date=initial,
                             final_due_date=final)
    except db.peewee.IntegrityError:
        print('cannot create assignment with duplicate name')


def alter(assignment, initial, final):
    alterations = {}
    if initial is not None:
        alterations[db.Assignment.initial_due_date] = initial
    if final is not None:
        alterations[db.Assignment.final_due_date] = final
    if not alterations:
        return print('At least one new date must be specified')
    query = (db.Assignment
             .update(alterations)
             .where(db.Assignment.name == assignment))
    if query.execute() < 1:
        print(f'no such assignment {assignment}')


def remove(assignment):
    query = (db.Assignment
             .delete()
             .where(db.Assignment.name == assignment))
    if query.execute() < 1:
        print(f'no such assignment {assignment}')


def dump():
    print(' --- Assignments ---')
    for asn in db.Assignment.select():
        print(f'''{asn.name}:
\tInitial: {asn.initial_due_date}
\tFinal: {asn.final_due_date}''')


def reload():
    import os
    import signal
    os.kill(1, signal.SIGUSR1)


if __name__ == '__main__':
    exit(main())
