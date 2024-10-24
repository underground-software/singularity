#!/usr/bin/env python3

import argparse
import git
import sys
import tempfile

import db
import orbit.db
import mailman.db


PUSH_URL = 'http://git:8000/cgi-bin/git-receive-pack/grading.git'
PULL_URL = 'http://git:8000/grading.git'
REMOTE_NAME = 'grading'

tags_to_remove = []


def promote_tag(repo, tag_id, promoted_tag_name, msg):
    if not tag_id:
        return

    latest_tag = repo.tags[tag_id]
    if promoted_tag_name not in repo.tags:
        repo.create_tag(promoted_tag_name, ref=latest_tag.commit, message=msg)
    elif latest_tag.commit != repo.tags[promoted_tag_name].commit:
        repo.delete_tag(promoted_tag_name)
        tags_to_remove.append(f':refs/tags/{promoted_tag_name}')
        repo.create_tag(promoted_tag_name, ref=latest_tag.commit, message=msg)


def update_tags(assignment=None, component=None, user=None):
    assignments = ([assignment] if assignment
                   else [a.name for a in db.Assignment.select()])
    components = ([component] if component
                  else ['initial', 'review1', 'review2', 'final'])
    users = ([user] if user
             else [u.username for u in orbit.db.User.select()])

    grd_tbl = mailman.db.Gradeable
    s0 = grd_tbl.select().order_by(-grd_tbl.timestamp)
    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.clone_from(PULL_URL, repo_path)
        repo.create_remote(REMOTE_NAME, PUSH_URL)
        repo.config_writer().set_value('user', 'name', 'denis').release()
        (repo.config_writer().set_value('user', 'email', 'denis@denis')
                             .release())
        for asmt in assignments:
            s1 = s0.where(grd_tbl.assignment == asmt)
            for cmpt in components:
                s2 = s1.where(grd_tbl.component == cmpt)
                for usr in users:
                    sub_entry = s2.where(grd_tbl.user == usr).first()
                    tag_id = sub_entry.submission_id if sub_entry else None
                    msg = sub_entry.status if sub_entry else None
                    promote_tag(repo, tag_id, f'{usr}_{asmt}_{cmpt}', msg)

        for tag in tags_to_remove:
            repo.git.push(REMOTE_NAME, tag)
        repo.git.push(REMOTE_NAME, tags=True)


if __name__ == '__main__':
    p = argparse.ArgumentParser(prog='update_tags',
                                description='Set/update git tags to mark the '
                                            'latest grade-worthy submissions '
                                            'in the grading git repo.')
    p.add_argument('-a', '--assignment',
                   help='Assignment to update. Update all if arg is not '
                        'provided.')
    p.add_argument('-c', '--component',
                   help='Initial/peer/final component of the specified '
                        'assignment. Update all if arg is not provided.')
    p.add_argument('-u', '--user',
                   help='User whose tags you wish to update. Update all if '
                   'arg is not provided.')
    args = p.parse_args(sys.argv[1:])

    update_tags(args.assignment, args.component, args.user)
