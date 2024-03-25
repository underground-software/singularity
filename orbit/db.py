import sqlite3
import config
# nickname  table name
# USR => users
# SES => sessions
# REG => newusers
import sys


def _do(cmd, reps=(), set_=False, get_=False):
    if config.sql_verbose:
        print("SQL", cmd, file=sys.stderr)
    reps = (lambda x: x if type(x) is tuple else (x,))(reps)
    dat = None
    con = sqlite3.connect(config.database)
    new = con.cursor()
    ret = new.execute(cmd, reps)
    if get_:
        dat = ret.fetchall()
        if len(dat) < 1:
            dat = [None]
        if config.sql_verbose:
            print("SQLRET", dat, file=sys.stderr)
        # works when get lookup fails
    if set_:
        ret.execute("COMMIT;")
    con.close()
    return dat


def _set(cmd, reps=()): return _do(cmd, reps, set_=True, get_=True)
def _get(cmd, reps=()): return _do(cmd, reps, get_=True)

# users table interface

USR_PWDHASHFOR_USERNAME = """
SELECT pwdhash
FROM users
WHERE username = ?;
""".strip()
def usr_pwdhashfor_username(usn): return _get(USR_PWDHASHFOR_USERNAME, usn)


USR_INS = """
INSERT INTO users (username, pwdhash, student_id)
VALUES (?, ?, ?);
""".strip()
def usr_ins(usr): return _set(USR_INS, usr)


USR_DELBY_USERNAME = """
DELETE FROM users
WHERE username = ?
RETURNING username;
""".strip()
def usr_delby_username(usn): return _set(USR_DELBY_USERNAME, usn)


USR_SETPWDHASH_USERNAME = """
UPDATE users
SET pwdhash = ?
WHERE username = ?;
""".strip()
def usr_setpwdhash_username(usr): return _set(USR_SETPWDHASH_USERNAME, usr)


USR_GET = """
SELECT id, username, pwdhash, student_id
FROM users;
""".strip()
def usr_get(): return _get(USR_GET)


USR_GETBY_USERNAME = """
SELECT id, username, pwdhash, student_id
FROM users
WHERE username = ?;
""".strip()
def usr_getby_username(usn): return _get(USR_GETBY_USERNAME, usn)


# registration table inferface

REG_INS = """
INSERT INTO newusers (username, password, student_id)
VALUES (?,?,?);
""".strip()
def reg_ins(tpl): return _set(REG_INS, tpl)


REG_GETBY_STUID = """
SELECT registration_id, username, password
FROM newusers
WHERE student_id = ?;
""".strip()
def reg_getby_stuid(sid): return _get(REG_GETBY_STUID, sid)


REG_DELBY_REGID = """
DELETE FROM newusers
WHERE registration_id = ?;
""".strip()
def reg_delby_regid(rid): return _set(REG_DELBY_REGID, rid)
