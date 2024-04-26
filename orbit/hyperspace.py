#!/usr/bin/env python3

import argparse
import sys
import bcrypt
import db
from datetime import datetime

# internal imports
import config
from radius import Session


def errx(msg):
    print(msg, file=sys.stderr)
    exit(1)


def need(a, u=False, p=False, t=False):
    if u and a.username is None:
        errx("Need username. Bye.")
    if p and a.password is None:
        errx("Need password. Bye.")
    if t and a.token is None:
        errx("Need token. Bye.")


def nou(u):
    errx(f'no such user "{u}". Bye.')


def do_query_username(args):
    need(args, u=True)
    if not (user := db.User.get_or_none(db.User.username == args.username)):
        nou(args.username)
    print(f'Username        : {user.username}\n'
          f'Hashed Password : {user.pwdhash}\n'
          f'Student ID      : {user.student_id}')


def do_validate_token(args):
    need(args, t=True)

    ses = db.Session.get_or_none(db.Session.token == args.token)
    if ses:
        print(ses.username)
    else:
        print('null')


def do_drop_session(args):
    need(args, u=True)
    query = (db.Session
             .delete()
             .where(db.Session.username == args.username)
             .returning(db.Session))

    if ses := next(iter(query.execute()), None):
        print(ses.username)
    else:
        print('null')


def do_create_session(args):
    need(args, u=True)
    ses = Session(username=args.username)
    print(ses.token)


def do_validate_creds(args):
    need(args, u=True, p=True)
    if not (user := db.User.get_or_none(db.User.username == args.username)):
        nou(args.username)
    if not bcrypt.checkpw(args.password.encode('utf-8'),
                          user.pwdhash.encode('utf-8')):
        print('null')
        return
    print(f'credentials(username: {args.username}, password:{args.password})')


def do_change_password(args):
    need(args, u=True, p=True)
    new_hash = do_bcrypt_hash(args, get=True)
    query = (db.User
             .update({db.User.pwdhash: new_hash})
             .where(db.User.username == args.username))
    if query.execute() < 1:
        nou(args.username)
    print(f'credentials(username: {args.username}, password:{args.password})')


def do_delete_user(args):
    need(args, u=True)
    query = (db.User
             .delete()
             .where(db.User.username == args.username))
    if query.execute() < 1:
        nou(args.username)
    print(args.username)


def do_bcrypt_hash(args, get=False):
    need(args, p=True)
    res = str(bcrypt.hashpw(bytes(args.password, "UTF-8"),
                            bcrypt.gensalt()), "UTF-8")
    if get:
        return res
    else:
        print(res)


def do_newuser(args):
    need(args, u=True, p=True)
    new_hash = do_bcrypt_hash(args, get=True)
    try:
        db.User.create(username=args.username, pwdhash=new_hash,
                       student_id=args.studentid)
        if args.studentid:
            db.Registration.create(username=args.username,
                                   password=args.password,
                                   student_id=args.studentid)
        do_validate_creds(args)
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
    parser.add_argument('-t', '--token', help='Token to operate with')
    parser.add_argument('-e', '--exercise',
                        help='Assignment/Exercise to operate with')

    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('-r', '--roster', action='store_const',
                         help='List of all known valid usernames',
                         dest='do', const=do_roster)
    actions.add_argument('-n', '--newuser', action='store_const',
                         help='Create a new user from supplied credentials',
                         dest='do', const=do_newuser)
    actions.add_argument('-s', '--session', action='store_const',
                         help='Check valitity of supplied token',
                         dest='do', const=do_validate_token)
    actions.add_argument('-d', '--dropsession', action='store_const',
                         help='Drop any existing valid session for supplied username',  # NOQA: E501
                         dest='do', const=do_drop_session)
    actions.add_argument('-c', '--createsession', action='store_const',
                         help='Create session for supplied username',
                         dest='do', const=do_create_session)
    actions.add_argument('-v', '--validatecreds', action='store_const',
                         help='Create session for supplied username',
                         dest='do', const=do_validate_creds)
    actions.add_argument('-m', '--mutatepassword', action='store_const',
                         help='Change password for supplied username to supplied password',  # NOQA: E501
                         dest='do', const=do_change_password)
    actions.add_argument('-w', '--withdrawuser', action='store_const',
                         help='Delete ("withdraw") the supplied username',
                         dest='do', const=do_delete_user)
    actions.add_argument('-b', '--bcrypthash', action='store_const',
                         help='Generate bcrypt hash from supplied password',
                         dest='do', const=do_bcrypt_hash)
    actions.add_argument('-l', '--listsessions', action='store_const',
                         help='List of all known sessions (some could be invalid)',  # NOQA: E501
                         dest='do', const=do_list_sessions)
    actions.add_argument('-q', '--queryuser', action='store_const',
                         help='Get information about supplied username if valid',  # NOQA: E501
                         dest='do', const=do_query_username)

    args = parser.parse_args(raw_args)
    if (args.do):
        args.do(args)
    else:
        print("Nothing to do. Tip: -h")


if __name__ == "__main__":
    hyperspace_main(sys.argv[1:])
