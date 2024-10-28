import subprocess

import orbit.db
import mailman.db


def user_to_sub(assignment, component):
    submission_ids = {}
    grd_tbl = mailman.db.Gradeable
    relevant_gradeables = (grd_tbl.select()
                           .where(grd_tbl.assignment == assignment)
                           .where(grd_tbl.component == component)
                           .order_by(grd_tbl.timestamp.desc()))
    for user in orbit.db.User.select():
        username = user.username
        sub = (relevant_gradeables
               .where(grd_tbl.user == username)
               .first())
        submission_ids[user.username] = sub.submission_id if sub else None

    return submission_ids


def release_subs(sub_ids):
    journal_data = bytearray()
    for id in sub_ids:
        with open(f'/var/lib/email/patchsets/{id}', 'rb') as f:
            journal_data += f.read()
    subprocess.run(['/usr/local/bin/append_journal',
                    '/var/lib/email/journal/journal'],
                   input=journal_data, check=True)


def update_tags(assignment, component):
    grd_tbl = mailman.db.Gradeable
    subs = (grd_tbl.select()
                   .order_by(-grd_tbl.timestamp)
                   .where(grd_tbl.assignment == assignment)
                   .where(grd_tbl.component == component))
    for user in orbit.db.User.select():
        user_sub = subs.where(grd_tbl.user == user.username).first()
        tag_id = user_sub.submission_id if user_sub else None
        print(f'update tag called on {user.username}\'s {component} '
              f'{assignment} submission with tag id {tag_id}')
