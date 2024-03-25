import config
from peewee import Model, IntegerField, CharField, BooleanField, SqliteDatabase
from typing import Optional, Self

DB = SqliteDatabase(config.database)

# Helpful peewee orm docs:
# http://docs.peewee-orm.com/en/latest/peewee/models.html
# http://docs.peewee-orm.com/en/latest/peewee/querying.html


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
    username = CharField()
    expiry = CharField()

    def __repr__(self):
        return f'Session(token={self.token}, username={self.username}, expiry={self.expiry})'  # noqa: 501 (long line)

    def __str__(self):
        return repr(self)

    def get_by_token(token: str) -> Optional[Self]:
        return Session.get_or_none(Session.token == token)

    def get_by_username(username: str) -> list[Self]:
        return list(Session.select().where(Session.username == username))

    def get_all() -> list[Self]:
        return list(Session.select())

    def insert_new(token: str, username: str, expiry: str):
        Session.create(token=token, username=username, expiry=expiry)

    def set_expiry(token: str, expiry: str):
        Session.update(expiry=expiry).where(Session.token == token).execute()

    def del_by_token(token: str) -> Optional[Self]:
        res = Session.delete()                      \
                     .where(Session.token == token) \
                     .returning(Session)            \
                     .execute()
        if res.count > 0:
            return res[0]

    def del_by_username(username: str) -> list[Self]:
        res = Session.delete()                            \
                     .where(Session.username == username) \
                     .returning(Session)                  \
                     .execute()
        return list(res)


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


# automatically create tables
# this actually does IO, creates orbit.db calls CREATE TABLE, etc.
# maybe this should move to some initializer function
DB.create_tables(BaseModel.__subclasses__())
