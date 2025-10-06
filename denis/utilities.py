import os
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
                           .order_by(-grd_tbl.timestamp))
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
    gbls = (grd_tbl.select()
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
            user_gbl = gbls.where(grd_tbl.user == user.username).first()
            if not user_gbl or (id := user_gbl.submission_id) not in repo.tags:
                msg = 'No gradeable submission'
                to_promote = repo.tags['EMPTY']
            else:
                msg = user_gbl.auto_feedback
                to_promote = repo.tags[id]
            repo.create_tag(new_tag_name, ref=to_promote.commit, message=msg)

        repo.git.push(REMOTE_NAME, tags=True)

    return updated_tags


def check_corrupt_or_missing(repo, tag, username_to_subs):
    [assignment, component, user] = tag.split('_', 2)

    gradable = username_to_subs[user]

    msg = 'corruption and existence check'
    msg += '\n'
    msg += '------------------------------'
    msg += '\n\n'
    if not gradable or gradable.auto_feedback[-1] == '!':
        repo.git.execute(['git', 'notes', '--ref=grade', 'add', tag, '-m', '0'])
        if not gradable:
            msg += 'automatic 0 due to missing submission!'
        else:
            msg += 'automatic 0 due to corrupt submission!'
    else:
        msg += 'Patchset applies.'

    msg += '\n\n'
    return msg


def check_signed_off_by(repo, tag):
    [_, _, user] = tag.split('_', 2)
    hostname = os.getenv("SINGULARITY_HOSTNAME")

    usr_tbl = orbit.db.User
    fullname = (usr_tbl.select()
                       .where(usr_tbl.username == user)
                       .first()).fullname

    msg = 'signed off by check'
    msg += '\n'
    msg += '-------------------'
    msg += '\n\n'

    commits = repo.git.execute(['git', 'rev-list', '--reverse', tag]).split('\n')
    expected_dco = f'Signed-off-by: {fullname} <{user}@{hostname}>'
    nr_flawless = 0
    for i, commit in enumerate(commits):
        patch = repo.git.execute(['git', 'show', commit])
        if expected_dco in patch:
            nr_flawless += 1
        elif ('Signed-off-by:' in patch) or ('signed-off-by:' in patch):
            msg += f'patch {i}: double check Signed-off-by\n'
        else:
            msg += f'patch {i}: no Signed-off-by line found\n'

    if len(commits) == nr_flawless:
        msg += 'All signed off by lines present as expected.\n'

    msg += '\n'
    return msg


def check_subject_tag(repo, tag):
    [assignment, component, user] = tag.split('_', 2)

    msg = 'subject tag check'
    msg += '\n'
    msg += '-----------------'
    msg += '\n\n'

    commits = repo.git.execute(['git', 'rev-list', '--reverse', tag]).split('\n')

    sub_tbl = mailman.db.Submission
    relevant_submissions = (sub_tbl.select()
                            .where(sub_tbl.recipient == assignment)
                            .where(sub_tbl.user == user)
                            .order_by(sub_tbl.timestamp.desc()))
    expected_revision_number = relevant_submissions.count()

    nr_commits = len(commits)

    nr_flawless = 0
    for i, commit in enumerate(commits):
        # from 0/n .. n/n
        expected_tag = f'[{"RFC " if component == "initial" else ""}PATCH v{expected_revision_number} {i}/{nr_commits - 1}]'
        patch = repo.git.execute(['git', 'show', commit])
        if expected_tag in patch:
            nr_flawless += 1
        else:
            msg += f'patch {i}: subject tag not detected (expected "{expected_tag}")\n'

    if nr_commits == nr_flawless:
        msg += 'Found all expected correct subject tags\n'

    return msg


def run_automated_checks(tags, username_to_subs, peer=False):
    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.clone_from(PULL_URL, repo_path)

        remote = repo.create_remote(REMOTE_NAME, PUSH_URL)
        remote.fetch('refs/notes/*:refs/notes/*')
        configure_repo(repo)

        for tag in tags:
            msg = 'Automated tests by denis'
            msg += '\n\n'
            msg += check_corrupt_or_missing(repo, tag, username_to_subs)

            if msg[-3] != '!' and not peer:
                msg += '\n\n'
                msg += check_signed_off_by(repo, tag)
                msg += check_subject_tag(repo, tag)

            repo.git.execute(['git', 'notes', '--ref=denis', 'add', tag, '-m', msg])

        remote.push('refs/notes/*:refs/notes/*')
