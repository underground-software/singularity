import re
import os
import git
import copy
import subprocess
import tempfile
import difflib

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
    [assignment, component, user] = tag.split('_')

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
        msg += 'PATCHSET APPLIES'

    msg += '\n\n'
    return msg


def check_signed_off_by(repo, tag):
    [_, _, user] = tag.split('_')
    hostname = os.getenv("HOSTNAME")

    msg = 'signed off by check'
    msg += '\n'
    msg += '-------------------'
    msg += '\n\n'

    commits = reversed(repo.git.execute(['git', 'rev-list', tag]).split('\n'))

    expected_dco = f'Signed-off-by: {user} <{user}@{hostname}>'

    missing = []
    malformed = []
    for i, commit in enumerate(commits):
        patch = repo.git.execute(['git', 'show', commit])

        match = re.search(r'^\s+(Signed-off-by:\s+.+\s+<.+>)$', patch, re.MULTILINE)
        if match:
            found_dco = match.group(1)
            if expected_dco == found_dco:
                continue
            malformed.append(f'malformed line {found_dco} in patch {i}\n')
        else:
            missing.append(f'{i}')

    if (n := len(missing)) > 0:
        msg += f'Signed-off-by: missing from patch{"es" if n > 1 else ""} {",".join(missing)}\n'
    for mal in malformed:
        msg += mal

    if len(missing) == len(malformed) == 0:
        msg += 'ALL PATCHES SIGNED OFF CORRECTLY\n'

    msg += '\n'
    return msg


def check_subject_tag(repo, tag):
    [_, component, _] = tag.split('_')

    msg = 'subject tag check'
    msg += '\n'
    msg += '-----------------'
    msg += '\n\n'

    commits = reversed(repo.git.execute(['git', 'rev-list', tag]).split('\n'))
    # from 0/n .. n/n
    expected_max_index = str(len(list(copy.copy(commits))) - 1)

    rfc_offset = 0
    found_version = None
    bad = {}
    for i, commit in enumerate(commits):
        patch = repo.git.execute(['git', 'show', commit])

        match = re.search(r'^\s*\[(.*)\].*', patch, re.MULTILINE)
        if not match:
            msg += f'patch {i} no tag found!\n'
            bad[i] = True
            continue
        subj_tag = match.group(1)
        msg += f'patch {i} tag {subj_tag}\n'
        subj_tag_parts = subj_tag.split(' ')
        match component:
            case 'initial' if subj_tag_parts[0] == 'RFC':
                msg += 'initial submission correctly labeled RFC\n'
                rfc_offset = 1
            case 'initial' if subj_tag_parts[0] == 'PATCH':
                msg += 'initial submission missing RFC!\n'
                bad[i] = True
            case 'final' if subj_tag_parts[0] == 'RFC':
                msg += 'final submission incorrectly labeled RFC!\n'
                rfc_offset = 1
                bad[i] = True
            case 'final' if subj_tag_parts[0] == 'PATCH':
                msg += 'final submission correctly non RFC\n'

        if subj_tag_parts[rfc_offset] != 'PATCH':
            msg += 'tag missing "PATCH" in expected place\n'
            bad[i] = True

        if found_version is None:
            found_version = subj_tag_parts[rfc_offset+1]
        elif (this_version := subj_tag_parts[rfc_offset+1]) != found_version:
            msg += f'tag version mismatch: expected {found_version} found {this_version}!\n'
            bad[i] = True

        [this_index, max_index] = subj_tag_parts[rfc_offset+2].split('/')
        if this_index != str(i):
            msg += f'patch index mismatch: expected {i} found {this_index}'
            bad[i] = True

        if max_index != expected_max_index:
            msg += f'patch max index mismatch: expected {expected_max_index} found {max_index}'
            bad[i] = True

    if not any(bad):
        msg += 'ALL SUBJECT TAGS IN CORRECT FORMAT\n'

    return msg


def check_diffstat(repo, tag):
    msg = 'diffstat check'
    msg += '\n'
    msg += '--------------'
    msg += '\n\n'

    root = repo.git.execute(['git', 'rev-list', '--max-parents=0', tag])
    calculated_diffstat = repo.git.execute(['git', 'diff', '--stat', '--summary', f'{root}..{tag}'])
    cover = repo.git.execute(['git', 'show', root])
    cover_lines = [line.strip() for line in cover.split('\n')]

    rev_diffstat = []
    last = None
    collect = False
    for i in reversed(cover_lines):
        if collect:
            if len(i) == 0:
                break
            rev_diffstat.append(f' {i}')
        if len(i) == 0 and last == '--':
            collect = True
        last = i

    cover_diffstat = '\n'.join(reversed(rev_diffstat))
    diff_diffstat = '\n'.join(difflib.unified_diff(calculated_diffstat.split(), cover_diffstat.split()))

    msg += 'diffstat diff'
    msg += '\n'
    msg += diff_diffstat if len(diff_diffstat) > 0 else 'NO DIFFERENCE: DIFFSTAT VERIFIED'
    msg += '\n\n'

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
                msg += check_diffstat(repo, tag)

            repo.git.execute(['git', 'notes', '--ref=denis', 'add', tag, '-m', msg])

        remote.push('refs/notes/*:refs/notes/*')
