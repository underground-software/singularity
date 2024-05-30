#!/usr/bin/env python3

import argparse
import bcrypt
import sys

from datetime import datetime

# internal imports
import config
import db


def errx(msg):
    print(msg, file=sys.stderr)
    exit(1)


def need(a, u=False, p=False):
    needed = []
    if u and a.username is None:
        needed.append('username')
    if p and a.password is None:
        needed.append('password')
    if needed:
        errx(f"Need {' and '.join(needed)}. Bye.")


def nou(u):
    errx(f'no such user "{u}". Bye.')


def do_drop_session(args):
    need(args, u=True)
    query = (db.Session
             .delete()
             .where(db.Session.username == args.username))

    if query.execute() < 1:
        errx('No session belonging to that user found')


def do_change_password(args):
    need(args, u=True, p=True)
    new_hash = do_bcrypt_hash(args)
    query = (db.User
             .update({db.User.pwdhash: new_hash})
             .where(db.User.username == args.username))
    if query.execute() < 1:
        nou(args.username)


def do_reset_password(args):
    need(args, u=True)
    query = (db.User
             .update({db.User.pwdhash: None})
             .where(db.User.username == args.username))
    if query.execute() < 1:
        nou(args.username)


def do_delete_user(args):
    need(args, u=True)
    query = (db.User
             .delete()
             .where(db.User.username == args.username))
    if query.execute() < 1:
        nou(args.username)


def do_bcrypt_hash(args):
    need(args, p=True)
    return bcrypt.hashpw(args.password.encode('utf-8'),
                         bcrypt.gensalt()).decode('utf-8')


def do_newuser(args):
    need(args, u=True)
    new_hash = None
    if args.password is not None:
        new_hash = do_bcrypt_hash(args)
    try:
        db.User.create(username=args.username, pwdhash=new_hash,
                       student_id=args.studentid)
    except db.peewee.IntegrityError as e:
        errx(f'cannot create user with duplicate field: "{e}"')


def do_roster(args):
    print('Users:')
    for u in db.User.select():
        print(f'{u.username}, {u.pwdhash}, {u.student_id}')


def do_list_sessions(args):
    print('Sessions:')
    for s in db.Session.select():
        expiry = datetime.fromtimestamp(s.expiry)
        print(f'{s.username} until {expiry}: {s.token}')


def hyperspace_main(raw_args):
    parser = argparse.ArgumentParser(prog='hyperspace',
                                     description='Administrate Orbit',
                                     epilog=f'{config.version_info}')

    parser.add_argument('-u', '--username', help='Username to operate with')
    parser.add_argument('-p', '--password', help='Password to operate with')
    parser.add_argument('-i', '--studentid', help='Student ID to operate with')

    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('-r', '--roster', action='store_const',
                         help='List of all known valid usernames',
                         dest='do', const=do_roster)
    actions.add_argument('-n', '--newuser', action='store_const',
                         help='Create a new user from supplied credentials',
                         dest='do', const=do_newuser)
    actions.add_argument('-m', '--mutatepassword', action='store_const',
                         help='Change password for supplied username to supplied password',  # NOQA: E501
                         dest='do', const=do_change_password)
    actions.add_argument('-c', '--clearpassword', action='store_const',
                         help='clear password for supplied username so they canot login',  # NOQA: E501
                         dest='do', const=do_reset_password)
    actions.add_argument('-w', '--withdrawuser', action='store_const',
                         help='Delete ("withdraw") the supplied username',
                         dest='do', const=do_delete_user)
    actions.add_argument('-l', '--listsessions', action='store_const',
                         help='List of all known sessions (some could be invalid)',  # NOQA: E501
                         dest='do', const=do_list_sessions)
    actions.add_argument('-d', '--dropsession', action='store_const',
                         help='Drop any existing valid session for supplied username',  # NOQA: E501
                         dest='do', const=do_drop_session)

    args = parser.parse_args(raw_args)
    if (args.do):
        args.do(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    hyperspace_main(sys.argv[1:])
