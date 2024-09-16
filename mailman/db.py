#!/usr/bin/env python3

import peewee

DB = peewee.SqliteDatabase("/var/lib/mailman/submissions.db")


class BaseModel(peewee.Model):
    class Meta:
        database = DB
        strict_tables = True


class Submission(BaseModel):
    submission_id = peewee.TextField(unique=True)
    timestamp = peewee.IntegerField()
    user = peewee.TextField()
    recipient = peewee.TextField()
    email_count = peewee.IntegerField()
    in_reply_to = peewee.TextField(null=True)


if __name__ == '__main__':
    DB.create_tables(BaseModel.__subclasses__())
