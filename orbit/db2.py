import config
from peewee import *

DB = SqliteDatabase(config.database)

class BaseModel(Model):
    class Meta:
        database = DB


class User(BaseModel):
    id = IntegerField(primary_key=True)
    username = CharField(unique=True)
    pwdhash = CharField()
    lfx = BooleanField()
    student_id = IntegerField()


class Session(BaseModel):
    token = CharField(primary_key=True)
    username = CharField(unique=True)
    expiry = CharField()


class Submission(BaseModel):
    id = CharField(primary_key=True)
    username = CharField()
    time = CharField()
    _to = CharField()
    _from = CharField()
    email_ids = CharField()
    subjects = CharField()


class Assignment(BaseModel):
    web_id = CharField(primary_key=True)
    email_id = CharField()


class NewUser(BaseModel):
    id = IntegerField(primary_key=True)
    student_id = CharField(unique=True)
    username = CharField(unique=True)
    password = CharField()


# TODO move this information to some config file
def init_db():
    DB.create_tables([User, Session, Submission, Assignment, NewUser])
    ASSIGNMENTS = [
        ("setup", "introductions"),
        ("E0", "exercise0"),
        ("E1", "exercise1"),
        ("E2", "exercise2"),
        ("P0", "programming0"),
        ("P1", "programming1"),
        ("P2", "programming2"),
        ("F0", "final0"),
        ("F1", "final1"),
    ]
    Assignment.insert_many(ASSIGNMENTS, fields=(Assignment.web_id, Assignment.email_id)).execute()

