PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;
CREATE TABLE users (
	id integer primary key,
	username string UNIQUE NOT NULL,
	pwdhash string NOT NULL,
	student_id string UNIQUE);
CREATE TABLE sessions (
        token string PRIMARY KEY,
        username string UNIQUE NOT NULL,
        expiry string NOT NULL);
CREATE TABLE newusers (
	registration_id integer primary key,
	student_id string UNIQUE NOT NULL,
	username string UNIQUE NOT NULL,
	password string NOT NULL);
COMMIT;
