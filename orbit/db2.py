import config
from peewee import Model, IntegerField, CharField, SqliteDatabase, FieldAccessor  # noqa 501
from typing import Optional, Self

DB = SqliteDatabase(config.database)

# Helpful peewee orm docs:
# http://docs.peewee-orm.com/en/latest/peewee/models.html
# http://docs.peewee-orm.com/en/latest/peewee/querying.html


class BaseModel(Model):
    class Meta:
        database = DB

    # Custom string for table rows that is prettier than what peewee generates
    def __str__(self):
        self_ty = self.__class__
        fields = [name for name, val in vars(self_ty).items()
                  if isinstance(val, FieldAccessor)]
        fields = map(lambda name: f"{name}={getattr(self, name)}", fields)
        fields = ", ".join(fields)
        return f"{self_ty.__qualname__}({fields})"


class User(BaseModel):
    username = CharField(primary_key=True)
    pwdhash = CharField()
    student_id = IntegerField()

    def get_all() -> list[Self]:
        return list(User.select())

    def get_by_username(username: str) -> Optional[Self]:
        return User.get_or_none(User.username == username)

    def insert_new(username: str, pwdhash: str, student_id: int):
        User.create(username=username, pwdhash=pwdhash, student_id=student_id)

    def set_pwdhash(username: str, pwdhash: str):
        User.update(pwdhash=pwdhash).where(
            Session.username == username).execute()

    def del_by_username(username: str) -> Optional[Self]:
        res = User.delete()                         \
                  .where(User.username == username) \
                  .returning(User)                  \
                  .execute()
        if res.count > 0:
            return res[0]


class Session(BaseModel):
    token = CharField(primary_key=True)
    username = CharField()
    expiry = CharField()

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


class Registration(BaseModel):
    username = CharField(primary_key=True)
    password = CharField()
    student_id = CharField(unique=True)


# automatically create tables
# this actually does IO, creates orbit.db calls CREATE TABLE, etc.
# maybe this should move to some initializer function
DB.create_tables(BaseModel.__subclasses__())
