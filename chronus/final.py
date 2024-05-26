#!/usr/bin/env python3

import os

import orbit.db

# Block all students from seeing emails sent until
# we allow again after initial sub deadline
for user in orbit.db.User.select():
    os.system(f'restrict_access /var/lib/email/journal/journal -d {user.username}')
