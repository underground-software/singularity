import git
import subprocess
import tempfile

import orbit.db
import mailman.db


PUSH_URL = 'http://git:8000/cgi-bin/git-receive-pack/grading.git'
PULL_URL = 'http://git:8000/grading.git'
REMOTE_NAME = 'grading'


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
    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.clone_from(PULL_URL, repo_path)
        repo.create_remote(REMOTE_NAME, PUSH_URL)
        repo.config_writer().set_value('user', 'name', 'denis').release()
        (repo.config_writer().set_value('user', 'email', 'denis@denis')
                             .release())
        if 'EMPTY' not in repo.tags:
            repo.git.commit('--allow-empty', '-m', 'No gradeable submission.')
            repo.create_tag('EMPTY')

        for user in orbit.db.User.select():
            new_tag_name = f'{assignment}_{component}_{user.username}'
            if new_tag_name in repo.tags:
                print('Potential issue? Attempted to create duplicate tag '
                      f'{new_tag_name}')
                continue
            user_sub = subs.where(grd_tbl.user == user.username).first()
            if not user_sub or (id := user_sub.submission_id) not in repo.tags:
                msg = 'No gradeable submission'
                to_promote = repo.tags['EMPTY']
            else:
                msg = user_sub.status
                to_promote = repo.tags[id]
            repo.create_tag(new_tag_name, ref=to_promote.commit, message=msg)

        repo.git.push(REMOTE_NAME, tags=True)
