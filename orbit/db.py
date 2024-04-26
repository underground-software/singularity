#!/usr/bin/env python3
import sqlite3
import peewee
import config
# nickname  table name
# USR => users
# SES => sessions
# REG => newusers
import sys

DB = peewee.SqliteDatabase(config.database)


class BaseModel(peewee.Model):
    class Meta:
        database = DB
        strict_tables = True


class User(BaseModel):
    username = peewee.TextField(unique=True)
    pwdhash = peewee.TextField()
    student_id = peewee.TextField(unique=True, null=True)

    class Meta:
        table_name = 'users'


class Session(BaseModel):
    token = peewee.TextField(primary_key=True)
    username = peewee.TextField(unique=True)
    expiry = peewee.FloatField()

    class Meta:
        table_name = 'sessions'


class Registration(BaseModel):
    student_id = peewee.TextField(unique=True)
    username = peewee.TextField(unique=True)
    password = peewee.TextField()

    class Meta:
        table_name = 'newusers'


if __name__ == '__main__':
    DB.create_tables(BaseModel.__subclasses__())


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
