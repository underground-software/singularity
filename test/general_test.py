import os
import subprocess
import pytest
import requests_unixsocket
import socket
import smtplib
import poplib
import ssl
import base64
import urllib.parse
from requests.adapters import HTTPAdapter
from urllib3.connection import HTTPConnection
from urllib3.connectionpool import HTTPConnectionPool
from urllib3.util.ssl_ import create_urllib3_context
from email.message import EmailMessage
from pathlib import Path

CERT_PATH = "test/artifacts/ca_cert.pem"
REQ_OPTS = {
    "verify": CERT_PATH,
    "timeout": 10
}
HTTPS_SOCKET_PATH = "socks/https.sock"
POP3S_SOCKET_PATH = "./socks/pop3s.sock"
SMTPS_SOCKET_PATH = "./socks/smtps.sock"
REGISTER_PASS = ""


class SSLUnixSocketConnection(HTTPConnection):
    """Custom HTTPConnection that wraps a Unix socket with SSL."""

    def __init__(self, unix_socket_path, **kwargs):
        super().__init__("localhost", **kwargs)  # Dummy host (not used)
        self.unix_socket_path = unix_socket_path
        self.ssl_context = create_urllib3_context()
        self.ssl_context.load_verify_locations(CERT_PATH)

    def _new_conn(self):
        """Create a new wrapped SSL connection over a Unix domain socket."""
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(self.unix_socket_path)
        return self.ssl_context.wrap_socket(sock, server_hostname="localhost")


class SSLUnixSocketConnectionPool(HTTPConnectionPool):
    """Custom ConnectionPool for Unix socket wrapped with SSL."""

    def __init__(self, socket_path, **kwargs):
        super().__init__("localhost", **kwargs)  # Dummy host (not used)
        self.socket_path = socket_path

    def _new_conn(self):
        return SSLUnixSocketConnection(self.socket_path)


class SSLUnixSocketAdapter(HTTPAdapter):
    """Transport adapter to route requests over a Unix socket with SSL."""

    def __init__(self, socket_path, **kwargs):
        self.socket_path = socket_path
        super().__init__(**kwargs)

    def get_connection(self, url, proxies=None):
        return SSLUnixSocketConnectionPool(self.socket_path)


class UnixPOP3(poplib.POP3):
    def __init__(self, socket_path, certfile, timeout=30):
        self.timeout = timeout
        # Create SSL context and load certificate
        ssl_context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
        ssl_context.load_verify_locations(certfile)

        # Create and connect Unix domain socket
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(socket_path)
        # Wrap with SSL
        self.sock = ssl_context.wrap_socket(sock, server_hostname='localhost.localdomain')
        self.file = self.sock.makefile('rb')
        self._debugging = 0


def singularity_pop_login(user, pass_):
    mailbox = UnixPOP3(POP3S_SOCKET_PATH, CERT_PATH)
    mailbox.user(user)
    mailbox.pass_(pass_)
    return mailbox


def require(command):
    """Ensure a required command is available."""
    if subprocess.call(["which", command], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) != 0:
        pytest.exit(f"error: {command} command required yet absent")


REQUIRED_COMMANDS = ["jq", "flake8", "podman", "podman-compose"]
for cmd in REQUIRED_COMMANDS:
    require(cmd)


def run_shell_command(cmd, check=True):
    """Run a shell command and return its output."""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and result.returncode != 0:
        pytest.fail(f"Command failed: {cmd}\n---stdout---\n{result.stdout}\n---stderr---\n{result.stderr}")
    return result.stdout.strip()


def get_hostname():
    """Retrieve SINGULARITY_HOSTNAME from the .env file."""
    cmd = "set -o allexport; source ./.env; jq -r -n \"env.SINGULARITY_HOSTNAME\""
    return run_shell_command(cmd)


SINGULARITY_HOSTNAME = os.getenv("SINGULARITY_HOSTNAME", get_hostname())
DOCKER = os.getenv("DOCKER", "podman")
DOCKER_COMPOSE = os.getenv("DOCKER_COMPOSE", "podman-compose")


session = requests_unixsocket.Session()
session.mount("http+unix://", SSLUnixSocketAdapter(HTTPS_SOCKET_PATH))


def setup_module():
    """Setup before any tests run."""
    run_shell_command("flake8")
    run_shell_command("./script-lint.sh")
    os.makedirs("test/artifacts", exist_ok=True)
    for file in Path("artifacts").glob("*"):
        file.unlink()
    run_shell_command(f'{DOCKER} cp singularity_nginx_1:/etc/ssl/nginx/fullchain.pem {CERT_PATH}')


# Tests begin here


def test_registration_fails_before_user_creation():
    url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}/register"
    response = session.post(url, data={"student_id": "1234"}, **REQ_OPTS)
    assert "msg = no such student" in response.text


def test_login_fails_before_user_creation():
    url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}/login"
    response = session.post(url, data={"username": "user", "password": "pass"}, **REQ_OPTS)
    assert "msg = authentication failure" in response.text


def test_create_user():
    run_shell_command("orbit/warpdrive.sh -u user -i 1234 -n")


def test_registration_fails_with_wrong_id():
    url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}/register"
    response = session.post(url, data={"student_id": "123"}, **REQ_OPTS)
    assert "msg = no such student" in response.text


def test_registration_succeeds():
    url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}/register"
    response = session.post(url, data={"student_id": "1234"}, **REQ_OPTS)
    assert "msg = welcome to the classroom" in response.text
    global REGISTER_PASS
    REGISTER_PASS = response.text.split("Password: ")[1].split("<")[0].strip()


def test_registration_fails_when_id_used_again():
    url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}/register"
    response = session.post(url, data={"student_id": "1234"}, **REQ_OPTS)
    assert "msg = no such student" in response.text


def test_login_fails_when_credentials_invalid():
    url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}/login"
    response = session.post(url, data={"username": "user", "invalid": REGISTER_PASS}, **REQ_OPTS)
    assert "msg = authentication failure" in response.text


def test_login_succeeds():
    url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}/login"
    response = session.post(url, data={"username": "user", "password": REGISTER_PASS}, **REQ_OPTS)
    assert "msg = user authenticated by password" in response.text


def test_email_empty_list():
    mailbox = singularity_pop_login('user', REGISTER_PASS)

    lst = mailbox.list()[1]

    print(lst)
    print(lst[1:])
    # Get mailbox statistics
    num_messages = len(lst[1:])
    # Close connection
    mailbox.quit()
    assert num_messages == 0


def test_send_email():
    class UnixSMTP(smtplib.SMTP):
        def __init__(self, socket_path, certfile, timeout=30):
            # Create SSL context and load certificate
            ssl_context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH)
            ssl_context.load_verify_locations(certfile)

            # Create and connect Unix domain socket
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.connect(socket_path)

            # Wrap with SSL
            self.sock = ssl_context.wrap_socket(sock, server_hostname='localhost.localdomain')
            self.file = self.sock.makefile('rb')
            super().__init__()

    smtp = UnixSMTP(SMTPS_SOCKET_PATH, CERT_PATH)

    print(smtp.ehlo('localhost.localdomain'))
    print(smtp.docmd('AUTH', 'PLAIN ' + base64.b64encode(('\x00' + 'user' + '\x00' + REGISTER_PASS).encode('utf-8')).decode('ascii')))
    print(smtp.getreply())

    msg = EmailMessage()
    msg.set_content("To whom it may concern,\n\nBottom text")
    msg["Subject"] = "Message Subject"
    msg["From"] = f"user@{SINGULARITY_HOSTNAME}"
    msg["To"] = f"other@{SINGULARITY_HOSTNAME}"
    smtp.send_message(msg)
    # print(smtp.sendmail('user@localhost.localdomain', 'recipient@localhost.localdomain', 'Subject: Test Email\n\nThis is a test email.'))
    smtp.quit()


def test_email_empty_list_before_journal_update():
    mailbox = singularity_pop_login('user', REGISTER_PASS)

    lst = mailbox.list()[1]

    print(lst)
    print(lst[1:])
    # Get mailbox statistics
    num_messages = len(lst[1:])
    # Close connection
    mailbox.quit()
    assert num_messages == 0


def test_restricted_user_cannot_access_messages():
    run_shell_command("orbit/warpdrive.sh -u resu -p ssap -n")
    run_shell_command(f'{DOCKER_COMPOSE} exec denis /usr/local/bin/restrict_access /var/lib/email/journal/journal -d resu')
    run_shell_command(f'{DOCKER_COMPOSE} exec denis /usr/local/bin/init_journal /var/lib/email/journal/journal /var/lib/email/journal/temp /var/lib/email/mail')

    mailbox = singularity_pop_login('resu', 'ssap')

    lst = mailbox.list()[1]

    print(lst)
    print(lst[1:])
    # Get mailbox statistics
    num_messages = len(lst[1:])
    # Close connection
    mailbox.quit()
    assert num_messages == 0


def test_email_retrieval():
    mailbox = singularity_pop_login('user', REGISTER_PASS)

    msg = mailbox.retr(1)
    assert "Bottom text" in str(msg[1][-1])


def test_freshly_unrestricted_user_obtains_access_to_messages():
    run_shell_command(f'{DOCKER_COMPOSE} exec denis /usr/local/bin/restrict_access /var/lib/email/journal/journal -a resu')

    mailbox = singularity_pop_login('resu', 'ssap')

    lst = mailbox.list()[1]

    print(lst)
    print(lst[1:])
    # Get mailbox statistics
    num_messages = len(lst[1:])
    # Close connection
    mailbox.quit()
    assert num_messages == 1


def test_matrix_login_success():
    url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}/_matrix/client/r0/login"
    response = session.post(url, json={"type": "m.login.password", "user": f"@user:{SINGULARITY_HOSTNAME}", "password": REGISTER_PASS}, **REQ_OPTS)
    assert "access_token" in response.text


def test_matrix_login_invalid():
    url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}/_matrix/client/r0/login"
    response = session.post(url, json={"type": "m.login.password", "user": f"@user:{SINGULARITY_HOSTNAME}", "password": "wrongpass"}, **REQ_OPTS)
    assert "errcode" in response.text and "M_FORBIDDEN" in response.text
