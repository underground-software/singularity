#!/usr/bin/env python3

import argparse
import sys
import bcrypt
import db
import db2
from pprint import pprint
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


USR_FMT = """
Username        : {}
Hashed Password : {}
Student ID      : {}
""".strip()


def do_query_username(args):
    need(args, u=True)
    u = db2.User.get_by_username(args.username)
    if u is None:
        nou(args.username)
    print(USR_FMT.format(u.username, u.pwdhash, u.student_id))


def do_validate_token(args):
    need(args, t=True)

    if ses := db2.Session.get_by_token(args.token):
        print(ses.username)
    else:
        print('null')


def do_drop_session(args):
    need(args, u=True)
    dropped = db2.Session.del_by_username(args.username)
    print(dropped)


def do_create_session(args):
    need(args, u=True)
    ses = Session(username=args.username)
    print(ses.token)


def do_validate_creds(args):
    need(args, u=True, p=True)
    u, p = args.username, args.password
    user = db2.User.get_by_username(u)
    if user is None:
        nou(u)

    if bcrypt.checkpw(bytes(p, "UTF-8"), bytes(user.pwdhash, "UTF-8")):
        print('credentials(username: {}, password:{})'.format(u, p))
    else:
        print('null')


def do_change_password(args):
    need(args, u=True, p=True)
    u, _ = args.username, args.password
    if db2.User.get_by_username(u):
        db2.User.set_pwdhash(u, do_bcrypt_hash(args, get=True))
        do_validate_creds(args)
    else:
        nou(u)


def do_delete_user(args):
    need(args, u=True)
    if not db2.User.get_by_username(args.username):
        nou(args.username)
    db2.User.del_by_username(args.username)


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
    if db2.User.get_by_username(args.username):
        errx(f'cannot create duplicate user "{args.username}"')
    else:
        db2.User.insert_new(args.username, do_bcrypt_hash(
            args, get=True), args.studentid or 0)
    if args.studentid:
        db.reg_ins((args.username, args.password, args.studentid))
    do_validate_creds(args)


def do_roster(args):
    pprint(db2.User.get_all())


SES_FMT = """
{} until {}: {}
""".strip()


def do_list_sessions(args):
    raw_list = db2.Session.get_all()
    if len(raw_list) == 0:
        print("(no sessions)")
    else:
        print('\n'.join([SES_FMT.format(ses.username,
                                        datetime.fromtimestamp(ses.expiry),
                                        ses.token) for ses in raw_list]))


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
    actions.add_argument('-l', '--listsessions', action='store_const',
                         help='List of all known sessions (some could be invalid)',  # NOQA: E501
                         dest='do', const=do_list_sessions)
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
    actions.add_argument('-q', '--queryuser', action='store_const',
                         help='Get information about supplied username if valid',  # NOQA: E501
                         dest='do', const=do_query_username)

    args = parser.parse_args(raw_args)
    if (args.do):
        args.do(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    hyperspace_main(sys.argv[1:])
