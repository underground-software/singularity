#!/usr/bin/env python3

import peewee

DB = peewee.SqliteDatabase("/var/lib/mailman/submissions.db")


class BaseModel(peewee.Model):
    class Meta:
        database = DB
        strict_tables = True


class Submission(BaseModel):
    submission_id = peewee.TextField(unique=True)
    assignment = peewee.TextField()
    timestamp = peewee.IntegerField()
    user = peewee.TextField()
    status = peewee.TextField()


class PeerReview(BaseModel):
    review_id = peewee.TextField(unique=True)
    reviewer = peewee.TextField()
    reviewee = peewee.TextField()
    assignment = peewee.TextField()
    timestamp = peewee.IntegerField()


if __name__ == '__main__':
    DB.create_tables(BaseModel.__subclasses__())
