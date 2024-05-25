#!/usr/bin/env python3
import peewee

DB = peewee.SqliteDatabase("/var/lib/chronus/assignments.db")


class BaseModel(peewee.Model):
    class Meta:
        database = DB
        strict_tables = True


class Assignment(BaseModel):
    name = peewee.TextField(unique=True)
    initial_due_date = peewee.IntegerField()
    final_due_date = peewee.IntegerField()


if __name__ == '__main__':
    DB.create_tables(BaseModel.__subclasses__())
