import os
from email.message import EmailMessage
from pathlib import Path
from diameter import run_shell_command, RocketCrew, RocketRadio, SINGULARITY_HOSTNAME, DOCKER_COMPOSE, DOCKER, CERT_PATH

# The RocketCrew pilots the rocket into orbit
crew = RocketCrew()


def setup_module():
    """Setup before any tests run."""
    run_shell_command("flake8")
    run_shell_command("./script-lint.sh")
    os.makedirs("test/artifacts", exist_ok=True)
    for file in Path("artifacts").glob("*"):
        file.unlink()
    run_shell_command(f'{DOCKER} cp singularity_nginx_1:/etc/ssl/nginx/fullchain.pem {CERT_PATH}')


def test_registration_fails_before_user_creation():
    assert "msg = no such student" in crew.pilot('/register', data={"student_id": "1234"}).text


def test_login_fails_before_user_creation():
    assert "msg = authentication failure" in crew.pilot('/login', data={"username": "user", "password": "pass"}).text


def test_create_user():
    run_shell_command("orbit/warpdrive.sh -u user -i 1234 -n")


def test_registration_fails_with_wrong_id():
    assert "msg = no such student" in crew.pilot('/register', data={"student_id": "123"}).text


def test_registration_succeeds():
    response = crew.pilot('/register', data={"student_id": "1234"})
    assert "msg = welcome to the classroom" in response.text
    global REGISTER_PASS
    REGISTER_PASS = response.text.split("Password: ")[1].split("<")[0].strip()


def test_registration_fails_when_id_used_again():
    assert "msg = no such student" in crew.pilot('/register', data={"student_id": "1234"}).text


def test_login_fails_when_credentials_invalid():
    assert "msg = authentication failure" in crew.pilot('/login', data={"username": "user", "invalid": REGISTER_PASS}).text


def test_login_succeeds():
    assert "msg = user authenticated by password" in crew.pilot('/login', data={"username": "user", "password": REGISTER_PASS}).text


def test_email_empty_list():
    mailbox = RocketRadio('user', REGISTER_PASS, recv=True).pop

    lst = mailbox.list()[1]
    num_messages = len(lst[1:])
    mailbox.quit()

    assert num_messages == 0


def test_send_email():
    smtp = RocketRadio('user', REGISTER_PASS, send=True).smtp

    msg = EmailMessage()
    msg.set_content("To whom it may concern,\n\nBottom text")
    msg["Subject"] = "Message Subject"
    msg["From"] = f"user@{SINGULARITY_HOSTNAME}"
    msg["To"] = f"other@{SINGULARITY_HOSTNAME}"
    smtp.send_message(msg)
    # print(smtp.sendmail('user@localhost.localdomain', 'recipient@localhost.localdomain', 'Subject: Test Email\n\nThis is a test email.'))
    smtp.quit()


def test_email_empty_list_before_journal_update():
    mailbox = RocketRadio('user', REGISTER_PASS, recv=True).pop

    lst = mailbox.list()[1]
    num_messages = len(lst[1:])
    mailbox.quit()

    assert num_messages == 0


def test_restricted_user_cannot_access_messages():
    run_shell_command("orbit/warpdrive.sh -u resu -p ssap -n")
    run_shell_command(f'{DOCKER_COMPOSE} exec denis /usr/local/bin/restrict_access /var/lib/email/journal/journal -d resu')
    run_shell_command(f'{DOCKER_COMPOSE} exec denis /usr/local/bin/init_journal /var/lib/email/journal/journal /var/lib/email/journal/temp /var/lib/email/mail')

    mailbox = RocketRadio('resu', 'ssap', recv=True).pop

    lst = mailbox.list()[1]
    num_messages = len(lst[1:])
    mailbox.quit()

    assert num_messages == 0


def test_email_retrieval():
    mailbox = RocketRadio('user', REGISTER_PASS, recv=True).pop

    lst = mailbox.list()[1]
    assert len(lst[1:]) > 0

    msg = mailbox.retr(1)
    assert "Bottom text" in str(msg[1][-1])


def test_freshly_unrestricted_user_obtains_access_to_messages():
    run_shell_command(f'{DOCKER_COMPOSE} exec denis /usr/local/bin/restrict_access /var/lib/email/journal/journal -a resu')

    mailbox = RocketRadio('resu', 'ssap', recv=True).pop

    lst = mailbox.list()[1]
    num_messages = len(lst[1:])
    mailbox.quit()

    assert num_messages == 1


def test_matrix_login_success():
    response = crew.pilot('/_matrix/client/r0/login', json={"type": "m.login.password", "user": f"@user:{SINGULARITY_HOSTNAME}", "password": REGISTER_PASS})
    assert "access_token" in response.text


def test_matrix_login_invalid():
    response = crew.pilot('/_matrix/client/r0/login', json={"type": "m.login.password", "user": f"@user:{SINGULARITY_HOSTNAME}", "password": "wrongpass"})
    assert "errcode" in response.text and "M_FORBIDDEN" in response.text
