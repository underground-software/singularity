import re
import git
import pathlib
import sys
import ast
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


def do_check(repo, cover_letter, patches, asn):
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

    rubric = None
    if rubric_text := asn.rubric:
        try:
            rubric = ast.literal_eval(rubric_text)
        except SyntaxError:
            pass

    # check for correct # of patches in patchset
    if rubric and (rubric_count := len(rubric)) != (sub_count := len(patches)):
        return f'patch count {sub_count} violates expected rubric patch count of {rubric_count}!'

    for i, patch in enumerate(patches):
        patch_abspath = str(maildir / patch.msg_id)

        with open(patch_abspath, 'r') as patch_file:
            patch_content = patch_file.read()
        match = re.search(r'^\s+Signed-off-by:\s+.+\s+<(.+)@.+>$', patch_content, re.MULTILINE)
        if match:
            found_author = match.group(1)
        else:
            return f'illegal patch {i+1}: missing Signed-off-by line!'

        changelines = list(filter(lambda line: line.startswith('--- ') or line.startswith('+++ '), patch_content.split('\n')))
        for change in changelines:
            file = change.split(' ')[1].strip()
            if file == '/dev/null':
                continue
            first_dir = file.split('/')[1]
            if first_dir != found_author:
                file_fixed = file[2:]
                return f'illegal patch {i+1}: permission denied for path {file_fixed}!'

        # we assume first level directory is correct by this point
        # so we can replace it with some random template value
        # requirments: file is either being created of modified
        # therefore we assume some second of a pair contains the template author
        # rubric is a list of dictionaries mapping changepair tuples
        # to an integer counting the number of times that changepair is found
        if rubric:
            other = list(rubric[0].keys())[0][1].split('/')[1]
            for j in range(int(len(changelines)/2)):
                changepair = [changelines[2*j], changelines[2*j+1]]
                if changepair[0] != '--- /dev/null/':
                    changepair[0] = changepair[0].replace(found_author, other)
                if changepair[1] != '+++ /dev/null/':
                    changepair[1] = changepair[1].replace(found_author, other)
                try:
                    rubric[i][tuple(changepair)] += 1
                except KeyError:
                    pass
            # a changepair (e.g. ('--- fromfile', '+++ tofile') may appear
            # more than in the rubric o if modifications to a file
            # are more sparse than in the example used to generate the rubric
            if any(count < 1 for count in rubric[i].values()):
                return f'patch {i+1} violates the assignment rubric!'

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


def check(cover_letter, patches, submission_id, asn):
    with tempfile.TemporaryDirectory() as repo_path:
        repo = git.Repo.init(repo_path)
        with repo.config_writer() as config:
            config.set_value('user', 'name', 'mailman')
            config.set_value('user', 'email', 'mailman@mailman')
        status = do_check(repo, cover_letter, patches, asn)
        if status[-1] == '!':
            for patch in patches:
                patch_abspath = str(maildir / patch.msg_id)
                repo.git.execute(['git', 'commit', '--allow-empty', '-F', patch_abspath])
        tag_and_push(repo, submission_id, msg=status)
    return status


def apply_peer_review(email, submission_id, review_id):
    args = [*git_am_args, '--empty=keep']
    patch_abspath = str(maildir / email.msg_id)

    status = 'sucessfully stored peer review'

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
            status = 'failed to apply peer review'

    return status
