PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE users (
	id integer primary key,
	username text UNIQUE NOT NULL,
	pwdhash text NOT NULL,
	student_id text UNIQUE) STRICT;
CREATE TABLE sessions (
        token text PRIMARY KEY,
        username text UNIQUE NOT NULL,
        expiry real NOT NULL) STRICT;
CREATE TABLE newusers (
	student_id text UNIQUE NOT NULL,
	username text UNIQUE NOT NULL,
	password text NOT NULL) STRICT;
COMMIT;
