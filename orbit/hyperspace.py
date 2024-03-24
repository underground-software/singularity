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


USR_FMT = """
Orbit ID        : {}
Username        : {}
Hashed Password : {}
Student ID      : {}
""".strip()


def do_query_username(args):
    need(args, u=True)
    u = db.usr_getby_username(args.username)[0]
    if u is None:
        nou(args.username)
    print(USR_FMT.format(*u))


def do_validate_token(args):
    need(args, t=True)

    ses = db.ses_getby_token(args.token)[0]
    if ses:
        print(ses[1])
    else:
        print('null')


def do_drop_session(args):
    need(args, u=True)
    dropped = db.ses_delby_username(args.username)[0]
    if dropped:
        print(dropped[0])
    else:
        print('null')


def do_create_session(args):
    need(args, u=True)
    ses = Session(username=args.username)
    print(ses.token)


def do_validate_creds(args):
    need(args, u=True, p=True)
    u, p = args.username, args.password
    pwdhash = db.usr_pwdhashfor_username(u)[0]
    if pwdhash is None:
        nou(u)
    pwdhash = pwdhash[0]

    if bcrypt.checkpw(bytes(p, "UTF-8"), bytes(pwdhash, "UTF-8")):
        print('credentials(username: {}, password:{})'.format(u, p))
    else:
        print('null')


def do_change_password(args):
    need(args, u=True, p=True)
    u, _ = args.username, args.password
    if db.usr_getby_username(u)[0]:
        db.usr_setpwdhash_username((do_bcrypt_hash(args, get=True), u))
        do_validate_creds(args)
    else:
        nou(u)


def do_delete_user(args):
    need(args, u=True)
    deleted = db.usr_delby_username(args.username)[0]
    if deleted:
        print(deleted[0])
    else:
        print('null')


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
    if db.usr_getby_username(args.username)[0]:
        errx(f'cannot create duplicate user "{args.username}"')
    else:
        db.usr_ins((args.username, do_bcrypt_hash(args, get=True),
                    args.studentid or 0))
    if args.studentid:
        db.reg_ins((args.username, args.password, args.studentid))
    do_validate_creds(args)


def do_roster(args):
    r = db.usr_get()
    print(r)


SES_FMT = """
{} until {}: {}
""".strip()


def do_list_sessions(args):
    raw_list = db.ses_get()
    if raw_list[0] is None:
        print("(no sessions)")
    else:
        print('\n'.join([SES_FMT.format(session[1],
                                        datetime.fromtimestamp(session[2]),
                                        session[0]) for session in raw_list]))


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
