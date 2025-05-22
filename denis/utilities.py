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
        submission_ids[user.username] = sub if sub else None

    return submission_ids


def release_subs(sub_ids):
    journal_data = bytearray()
    for id in sub_ids:
        with open(f'/var/lib/email/patchsets/{id}', 'rb') as f:
            journal_data += f.read()
    subprocess.run(['/usr/local/bin/append_journal',
                    '/var/lib/email/journal/journal'],
                   input=journal_data, check=True)


def configure_repo(repo):
    with repo.config_writer() as config:
        config.set_value('user', 'name', 'denis')
        config.set_value('user', 'email', 'denis@denis')


def update_tags(assignment, component):
    grd_tbl = mailman.db.Gradeable
    subs = (grd_tbl.select()
                   .order_by(-grd_tbl.timestamp)
                   .where(grd_tbl.assignment == assignment)
                   .where(grd_tbl.component == component))
    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.clone_from(PULL_URL, repo_path)
        repo.create_remote(REMOTE_NAME, PUSH_URL)
        configure_repo(repo)
        if 'EMPTY' not in repo.tags:
            repo.git.commit('--allow-empty', '-m', 'No gradeable submission.')
            repo.create_tag('EMPTY')

        updated_tags = []
        for user in orbit.db.User.select():
            new_tag_name = f'{assignment}_{component}_{user.username}'
            updated_tags.append(new_tag_name)
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

    return updated_tags


def check_corrupt_or_missing(repo, tag, username_to_subs):
    [assignment, component, user] = tag.split('_')

    gradable = username_to_subs[user]

    msg = 'corruption and existence check'
    msg += '\n'
    msg += '------------------------------'
    msg += '\n\n'
    if not gradable or gradable.status[-1] == '!':
        repo.git.execute(['git', 'notes', '--ref=grade', 'add', tag, '-m', '0'])
        if not gradable:
            msg += 'automatic 0 due to missing submission!'
        else:
            msg += 'automatic 0 due to corrupt submission!'
    else:
        msg += 'PATCHSET APPLIES'

    msg += '\n\n'
    return msg


def run_automated_checks(tags, username_to_subs):
    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.clone_from(PULL_URL, repo_path)

        remote = repo.create_remote(REMOTE_NAME, PUSH_URL)
        remote.fetch('refs/notes/*:refs/notes/*')
        configure_repo(repo)

        for tag in tags:
            msg = 'Automated tests by denis'
            msg += '\n\n'
            msg += check_corrupt_or_missing(repo, tag, username_to_subs)
            repo.git.execute(['git', 'notes', '--ref=denis', 'add', tag, '-m', msg])

        remote.push('refs/notes/*:refs/notes/*')
