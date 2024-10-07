#!/usr/bin/env python3

import peewee

DB = peewee.SqliteDatabase('/var/lib/orbit/orbit.db')


class BaseModel(peewee.Model):
    class Meta:
        database = DB
        strict_tables = True


class User(BaseModel):
    username = peewee.TextField(unique=True)
    pwdhash = peewee.TextField(null=True)
    student_id = peewee.TextField(unique=True, null=True)


class Session(BaseModel):
    token = peewee.TextField(primary_key=True)
    username = peewee.TextField(unique=True)
    expiry = peewee.FloatField()


class Oopsie(BaseModel):
    user = peewee.TextField(primary_key=True)
    assignment = peewee.TextField()
    timestamp = peewee.IntegerField()


if __name__ == '__main__':
    DB.create_tables(BaseModel.__subclasses__())
