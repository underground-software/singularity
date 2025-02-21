import subprocess
import pytest
import socket
import smtplib
import base64
import os
import ssl
import poplib
import urllib.parse
import requests_unixsocket
from requests.adapters import HTTPAdapter
from pathlib import Path
from urllib3.connection import HTTPConnection
from urllib3.connectionpool import HTTPConnectionPool
from urllib3.util.ssl_ import create_urllib3_context

CERT_PATH = "test/artifacts/ca_cert.pem"
CREW_OPTS = {
    "verify": CERT_PATH,
    "timeout": 10
}
HTTPS_SOCKET_PATH = "socks/https.sock"
POP3S_SOCKET_PATH = "socks/pop3s.sock"
SMTPS_SOCKET_PATH = "socks/smtps.sock"
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
        return self.ssl_context.wrap_socket(sock, server_hostname="localhost.localdomain")


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


class UnixSocketInstaller():
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


class UnixSMTP(UnixSocketInstaller, smtplib.SMTP):
    def __init__(self, user, pass_):
        super().__init__(SMTPS_SOCKET_PATH, CERT_PATH)
        smtplib.SMTP.__init__(self)

        self.ehlo('localhost.localdomain')
        self.docmd('AUTH', 'PLAIN ' + base64.b64encode(('\x00' + user + '\x00' + pass_).encode('utf-8')).decode('ascii'))
        self.getreply()


class UnixPOP3(UnixSocketInstaller, poplib.POP3):
    def __init__(self, user, pass_, timeout=30):
        super().__init__(POP3S_SOCKET_PATH, CERT_PATH, timeout=timeout)
        self._debugging = 0
        self.user(user)
        self.pass_(pass_)

    def __len__(self):
        lst = self.list()[1]
        print(lst)
        msg_count = len(lst[1:])
        return msg_count


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
PODMAN = os.getenv("PODMAN", "podman")
PODMAN_COMPOSE = os.getenv("PODMAN_COMPOSE", "podman-compose")


class RocketCrew():
    def __init__(self):
        """Setup before any tests run."""
        run_shell_command("flake8")
        run_shell_command("./script-lint.sh")

        self.list = {}
        self.session = requests_unixsocket.Session()
        self.session.mount("http+unix://", SSLUnixSocketAdapter(HTTPS_SOCKET_PATH))

        os.makedirs("test/artifacts", exist_ok=True)
        for file in Path("test/artifacts").glob("*"):
            file.unlink()
        run_shell_command(f'{PODMAN} cp singularity_nginx_1:/etc/ssl/nginx/fullchain.pem {CERT_PATH}')

    def post(self, destination, data=None, json=None):
        """Make a post request to $destnation with optional data cargo (dict)"""
        url = f"http+unix://{urllib.parse.quote_plus(HTTPS_SOCKET_PATH)}{destination}"
        return self.session.post(url, data=data, json=json, **CREW_OPTS)

    def mkpop(self, user, pass_=None):
        return UnixPOP3(user, pass_ if pass_ is not None else self.list.get(user, ''))

    def mksmtp(self, user, pass_=None):
        return UnixSMTP(user, pass_ if pass_ is not None else self.list.get(user, ''))

    def create_user(self, user, pass_=None, id=None):
        assert user is not None

        append = f' -u {user}'
        if pass_ is not None:
            append += f' -p {pass_}'
            self.list[user] = pass_
        if id is not None:
            append += f' -i {id}'

        run_shell_command(f'orbit/warpdrive.sh -n{append}')


def execute_denis(command):
    run_shell_command(f'{PODMAN_COMPOSE} exec denis sh -c "{command}"')
