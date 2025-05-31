import git
import pathlib
import sys
import tempfile

REMOTE_PUSH_URL = 'http://git:8000/cgi-bin/git-receive-pack/grading.git'
REMOTE_PULL_URL = 'http://git:8000/grading.git'

MAIL_DIR_ABSPATH = "/var/lib/email/mail"
maildir = pathlib.Path(MAIL_DIR_ABSPATH)


def try_or_false(do, exc):
    try:
        do()
        return True
    except exc as e:
        print(e, file=sys.stderr)
        return False


def tag_and_push(repo, tag_name, msg=None):
    try:
        repo.create_tag(tag_name, message=msg)
        repo.create_remote('grading', REMOTE_PUSH_URL)
        repo.git.push('grading', tags=True)
        return True
    except git.GitCommandError as e:
        print(e, file=sys.stderr)
        return False


git_am_args = ['git', '-c', 'advice.mergeConflict=false',
               'am', '--keep']


def do_check(repo, cover_letter, patches):
    whitespace_errors = []

    def am_cover_letter(keep_empty=True):
        args = git_am_args.copy()
        if keep_empty:
            args.append("--empty=keep")
        repo.git.execute([*args, str(maildir/cover_letter.msg_id)])

    if try_or_false(lambda: am_cover_letter(keep_empty=False),
                    git.GitCommandError):
        return "missing cover letter!"

    repo.git.execute(["git", "am", "--abort"])
    if not try_or_false(lambda: am_cover_letter(keep_empty=True),
                        git.GitCommandError):
        return ("missing cover letter and "
                "first patch failed to apply!")

    for i, patch in enumerate(patches):
        patch_abspath = str(maildir / patch.msg_id)

        with open(patch_abspath, 'r') as patch_file:
            patch_content = patch_file.read()

        start = patch_content.find('From: <')+len('From: <')
        end = patch_content.find('@', start)
        if start == -1 or end == -1:
            return f'patch {i+1}: no author found (should be impossible)!'
        found_author = patch_content[start:end]

        changelines = list(filter(lambda line: line.startswith('--- ') or line.startswith('+++ '), patch_content.split('\n')))
        for change in changelines:
            file = change.split(' ')[1].strip()
            if file == '/dev/null':
                continue
            first_dir = file.split('/')[1]
            if first_dir != found_author:
                file_fixed = file[2:]
                return f'illegal patch {i+1}: permission denied for path {file_fixed}!'

        # Try and apply and fail if there are whitespace errors
        def do_git_am(extra_args=[]):
            repo.git.execute([*git_am_args, *extra_args, patch_abspath]),

        # If this fails, the patch may apply with whitespace errors
        if try_or_false(lambda: do_git_am(['--whitespace=error-all']),
                        git.GitCommandError):
            continue

        repo.git.execute(["git", "am", "--abort"])

        # Try again, if we succeed, count this patch as a whitespace error
        if try_or_false(lambda: do_git_am(), git.GitCommandError):
            whitespace_errors.append(str(i+1))
            continue

        # If we still fail, the patch does not apply
        return f'patch {i+1} failed to apply!'

    if whitespace_errors:
        return (f'whitespace error patch{"es" if len(whitespace_errors) > 1 else ""} '
                f'{",".join(whitespace_errors)}?')
    else:
        return 'patchset applies.'


def check(cover_letter, patches, submission_id):
    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.init(repo_path)
        with repo.config_writer() as config:
            config.set_value('user', 'name', 'mailman')
            config.set_value('user', 'email', 'mailman@mailman')
        auto_feedback = do_check(repo, cover_letter, patches)
        if auto_feedback[-1] == '!':
            for patch in patches:
                patch_abspath = str(maildir / patch.msg_id)
                repo.git.execute(['git', 'commit', '--allow-empty', '-F', patch_abspath])
        tag_and_push(repo, submission_id, msg=auto_feedback)
    return auto_feedback


def apply_peer_review(email, submission_id, review_id):
    args = [*git_am_args, '--empty=keep']
    patch_abspath = str(maildir / email.msg_id)

    auto_feedback = 'sucessfully stored peer review'

    with tempfile.TemporaryDirectory() as repo_path:
        try:
            repo = git.Repo.clone_from(REMOTE_PULL_URL, repo_path,
                                       multi_options=[f'--branch={review_id}',
                                                      '--single-branch',
                                                      '--no-tags'])
            with repo.config_writer() as config:
                config.set_value('user', 'name', 'mailman')
                config.set_value('user', 'email', 'mailman@mailman')
            repo.git.execute([*args, patch_abspath])
            tag_and_push(repo, submission_id)
        except git.GitCommandError as e:
            print(e, file=sys.stderr)
            auto_feedback = 'failed to apply peer review'

    return auto_feedback
