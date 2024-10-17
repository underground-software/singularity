import git
import pathlib
import sys
import tempfile

REMOTE_PUSH_URL = 'http://git:8000/cgi-bin/git-receive-pack/grading.git'
REMOTE_PULL_URL = 'http://git:8000/grading.git'

MAIL_DIR_ABSPATH = "/var/lib/email/mail"


def try_or_false(do, exc):
    try:
        do()
        return True
    except exc as e:
        print(e, file=sys.stderr)
        return False


def tag_and_push(repo_path, tag_name):
    try:
        repo = git.Repo(repo_path)
        repo.create_tag(tag_name)
        repo.create_remote('grading', REMOTE_PUSH_URL)
        repo.git.push('grading', tags=True)
        return True
    except git.GitCommandError as e:
        print(e, file=sys.stderr)
        return False


author_args = ['-c', 'user.name=mailman', '-c',
               'user.email=mailman@mailman']
git_am_args = ['git', *author_args, 'am', '--keep']


def do_check(repo_path, cover_letter, patches):
    repo = git.Repo.init(repo_path)
    maildir = pathlib.Path(MAIL_DIR_ABSPATH)
    whitespace_errors = []

    def am_cover_letter(keep_empty=True):
        args = git_am_args.copy()
        if keep_empty:
            args.append("--empty=keep")
        repo.git.execute([*args, str(maildir/cover_letter.msg_id)])

    if try_or_false(lambda: am_cover_letter(keep_empty=False),
                    git.GitCommandError):
        return "missing cover letter"

    repo.git.execute(["git", *author_args, "am", "--abort"])
    if not try_or_false(lambda: am_cover_letter(keep_empty=True),
                        git.GitCommandError):
        return ("missing cover letter and "
                "first patch failed to apply")

    for i, patch in enumerate(patches):
        patch_abspath = str(maildir / patch.msg_id)

        # Try and apply and fail if there are whitespace errors
        def do_git_am(extra_args=[]):
            repo.git.execute([*git_am_args, *extra_args, patch_abspath]),

        # If this fails, the patch may apply with whitespace errors
        if try_or_false(lambda: do_git_am(['--whitespace=error-all']),
                        git.GitCommandError):
            continue

        repo.git.execute(["git", *author_args, "am", "--abort"])

        # Try again, if we succeed, count this patch as a whitespace error
        if try_or_false(lambda: do_git_am(), git.GitCommandError):
            whitespace_errors.append(str(i+1))
            continue

        # If we still fail, the patch does not apply
        return f'patch {i+1} failed to apply'

    if whitespace_errors:
        return ('whitespace error patch(es) '
                f'{",".join(whitespace_errors)}')
    else:
        return 'patchset applies'


def check(cover_letter, patches, submission_id):
    with tempfile.TemporaryDirectory() as repo_path:
        status = do_check(repo_path, cover_letter, patches)
        tag_and_push(repo_path, submission_id)
    return status


def apply_peer_review(email, submission_id, review_id):
    maildir = pathlib.Path(MAIL_DIR_ABSPATH)
    args = [*git_am_args, '--empty=keep']
    patch_abspath = str(maildir / email.msg_id)

    status = 'sucessfully stored peer review'

    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.clone_from(REMOTE_PULL_URL, repo_path,
                                   multi_options=[f'--branch={review_id}',
                                                  '--single-branch',
                                                  '--no-tags'])
        try:
            repo.git.execute([*args, patch_abspath])
            tag_and_push(repo_path, submission_id)
        except git.GitCommandError as e:
            print(e, file=sys.stderr)
            status = 'failed to apply peer review'

    return status
