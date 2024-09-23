#!/usr/bin/env python3
import peewee

DB = peewee.SqliteDatabase("/var/lib/denis/assignments.db")


class BaseModel(peewee.Model):
    class Meta:
        database = DB
        strict_tables = True


class Assignment(BaseModel):
    name = peewee.TextField(unique=True)
    initial_due_date = peewee.IntegerField()
    peer_review_due_date = peewee.IntegerField()
    final_due_date = peewee.IntegerField()


class PeerReviewAssignment(BaseModel):
    assignment = peewee.TextField()
    reviewer = peewee.TextField()
    reviewee1 = peewee.TextField(null=True)
    reviewee2 = peewee.TextField(null=True)

    class Meta:
        indexes = ((('assignment', 'reviewer'), True),)


if __name__ == '__main__':
    DB.create_tables(BaseModel.__subclasses__())
