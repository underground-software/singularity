from email.message import EmailMessage
from diameter import RocketCrew, execute_denis, SINGULARITY_HOSTNAME


def setup_module():
    # The RocketCrew pilots the rocket into orbit
    global crew
    crew = RocketCrew()


def test_registration_fails_before_user_creation():
    assert "msg = no such student" in crew.post('/register', data={"student_id": "1234"}).text


def test_login_fails_before_user_creation():
    assert "msg = authentication failure" in crew.post('/login', data={"username": "user", "password": "pass"}).text


def test_create_user():
    crew.create_user('user', id='1234')


def test_registration_fails_with_wrong_id():
    assert "msg = no such student" in crew.post('/register', data={"student_id": "123"}).text


def test_registration_succeeds():
    response = crew.post('/register', data={"student_id": "1234"})
    assert "msg = welcome to the classroom" in response.text
    crew.list['user'] = response.text.split("Password: ")[1].split("<")[0].strip()


def test_registration_fails_when_id_used_again():
    assert "msg = no such student" in crew.post('/register', data={"student_id": "1234"}).text


def test_login_fails_when_credentials_invalid():
    assert "msg = authentication failure" in crew.post('/login', data={"username": "user", "invalid": crew.list['user']}).text


def test_login_succeeds():
    assert "msg = user authenticated by password" in crew.post('/login', data={"username": "user", "password": crew.list['user']}).text


def test_email_empty_list():
    assert len(crew.mkpop('user')) == 0


def test_send_email():
    smtp = crew.mksmtp('user')

    msg = EmailMessage()
    msg.set_content("To whom it may concern,\n\nBottom text")
    msg["Subject"] = "Message Subject"
    msg["From"] = f"user@{SINGULARITY_HOSTNAME}"
    msg["To"] = f"other@{SINGULARITY_HOSTNAME}"

    smtp.send_message(msg)
    smtp.quit()


def test_email_empty_list_before_journal_update():
    assert len(crew.mkpop('user')) == 0


def test_restricted_user_cannot_access_messages():
    crew.create_user('resu', pass_='ssap')
    execute_denis('/usr/local/bin/restrict_access /var/lib/email/journal/journal -d resu')
    execute_denis('cat /var/lib/email/patchsets/* | append_journal /var/lib/email/journal/journal')

    assert len(crew.mkpop('resu')) == 0


def test_email_retrieval():
    pop = crew.mkpop('user')
    assert len(pop) > 0
    # Check the last line of the first message, whici will be returned in the second entry of an array from POP3.retr()
    assert "Bottom text" in str(pop.retr(1)[1][-1])


def test_freshly_unrestricted_user_obtains_access_to_messages():
    execute_denis('/usr/local/bin/restrict_access /var/lib/email/journal/journal -a resu')
    assert len(crew.mkpop('resu')) == 1


def test_matrix_login_success():
    response = crew.post('/_matrix/client/r0/login', json={"type": "m.login.password", "user": f"@user:{SINGULARITY_HOSTNAME}", "password": crew.list['user']})
    assert "access_token" in response.text


def test_matrix_login_invalid():
    response = crew.post('/_matrix/client/r0/login', json={"type": "m.login.password", "user": f"@user:{SINGULARITY_HOSTNAME}", "password": "wrongpass"})
    assert "errcode" in response.text and "M_FORBIDDEN" in response.text
