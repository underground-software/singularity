#!/bin/env python3
#
# it's all one things now

import base64
import bcrypt
import html
import markdown
import os
import subprocess
import sys
import secrets
from http import HTTPStatus, cookies
from datetime import datetime, timedelta
from urllib.parse import parse_qs, urlparse

# === internal imports & constants ===
import config
import db
import mailman.db
import denis.db

sec_per_min = 60
min_per_ses = config.minutes_each_session_token_is_valid

with open(config.doc_header) as header:
    html_header = header.read()

# === utilities ===


def check_credentials(username, password):
    if not (user := db.User.get_or_none(db.User.username == username)):
        return False
    if not user.pwdhash:
        return False
    return bcrypt.checkpw(password.encode(), user.pwdhash.encode())


# === user session handling ===

class Session:
    """
    Session: User session management
             precondition for construction: validated authentication
             Manages the sessions db table
             construct with username to create a new session
             construct with environment to try load an active session

    ...

    Attributes
    ----------

    username : string
        The authenticated  username if self.valid()
        None otherwise

    token : string
        A valid token for user session if self.valid()
        None otherwise

    expiry : datetime.datetime
        The current session expiration date  if self.valid()
        None otherwise


    Methods
    -------
    valid()
        Get truth of whether this session is valid at time of call

    expired()
        Get truth of whether this $self.expiry is in the past

    expiry_fmt()
        Get a printable, formatted string of $self.expiry

    expiry_dt() : datetime.datetime
        Current session's expiration as unix timestamp

    """

    def __init__(self, env=None, username=None):
        self.token = None
        self.username = None
        self.expiry = None

        # initialize session from username and add new database entry
        if username:
            self.username = username
            self.token = self.mk_hash(username)
            self.expiry = datetime.now() + timedelta(minutes=min_per_ses)
            # creates a new session if one does not exist
            (db.Session
             .replace(username=self.username,
                      token=self.token,
                      expiry=self.expiry_ts())
             .execute())

        # try to load active session from database using user token
        else:
            if (raw := env.get("HTTP_COOKIE", None)):
                cok = cookies.BaseCookie('')
                cok.load(raw)
                res = cok.get('auth', cookies.Morsel()).value

                if (ses_found := db.Session.get_or_none(db.Session.token == res)):
                    self.token = ses_found.token
                    self.username = ses_found.username
                    self.expiry = datetime.fromtimestamp(ses_found.expiry)

    def end(self):
        db.Session.delete().where(db.Session.token == self.token).execute()
        self.token = None
        self.username = None
        self.expiry = None

    def valid(self):
        if not self.expired():
            return self.token

    def mk_hash(self, username):
        return secrets.token_hex()

    def expired(self):
        if (expiry := self.expiry) is None or datetime.now() > expiry:
            self.end()
            return True
        else:
            return False

    def expiry_fmt(self):
        return self.expiry.astimezone().isoformat()

    def expiry_ts(self):
        return self.expiry.timestamp()

    def mk_cookie_header(self):
        if self.token is None:
            return [('Set-Cookie', 'auth=')]
        cookie_fmt = 'auth={}; Max-Age={}; Path=/'
        max_age = sec_per_min * min_per_ses
        cookie_val = cookie_fmt.format(self.token, max_age)

        return [('Set-Cookie', cookie_val)]


class Rocket:
    """
    Rocket: Radius user request context (responsible for authentication)
            Limited external read access to users table

    ...

    Attributes
    ----------
    path_info : str
        Absolute path requested by user

    queries : dict
        Dictionary of queries parsed from client URL

    session : Session
        The current valid session token if it exists or None

    username : string
        The valid current session username or None if unauthenticated

    token : string
        The valid current session token or None if unauthenticated

    expiry : datetime.datetime
        The current session's expiry time and date or None if unauthenticated

    Methods
    -------

    expiry_fmt()
        returns a printable and nicely formatted expiry date and time string

    """

    # Eventually, toggle CGI or WSGI
    def read_body_args_wsgi(self):
        if self.method == "POST":
            return parse_qs(self.env['wsgi.input'].read(self.len_body()))
        else:
            return {None: '(no body)'}

    def __init__(self, env, start_response):
        self.env = env
        self._start_response = start_response
        self.path_info = self.env.get("PATH_INFO", "/")
        self.queries = parse_qs(self.env.get("QUERY_STRING", ""))
        self._session = None
        self._msg = "(silence)"
        # HTTP response headers specified by list of string pairs
        self.headers = []
        self.body_args = self.read_body_args_wsgi()

    def msg(self, msg):
        self._msg = msg

    def len_body(self):
        return int(self.env.get('CONTENT_LENGTH', "0"))

    @property
    def method(self):
        return self.env.get('REQUEST_METHOD', "GET")

    # when we use a session, check if the user has a token for
    # an existing session and act quietly load it if so
    # we don't do it in __init__ since that runs for public pages
    @property
    def session(self):
        if self._session is None:
            self._session = Session(env=self.env)
        # if the session is invalid, clear the user cookie
        if not self._session.valid():
            self.headers += self._session.mk_cookie_header()
        else:
            return self._session

    @property
    def username(self):
        if session := self.session:
            return session.username

    def body_args_query(self, key):
        return html.escape(
            self.body_args.get(key.encode(), [b''])[0].decode())

    def queries_query(self, key):
        return self.queries.get(key, [''])[0]

    # Attempt login using urelencoded credentials from request body
    def launch(self):
        new_ses = None
        if self.method == "POST":
            username = self.body_args_query('username')
            password = self.body_args_query('password')
            if (check_credentials(username, password)):
                new_ses = Session(username=username)
            if new_ses:
                self._session = new_ses
                self.headers += self._session.mk_cookie_header()
            return self.session

    # Logout of current session and clear user auth cookie
    def retire(self):
        self._session.end()
        self.headers += self._session.mk_cookie_header()

    def format_html(self, doc, title):
        # loads cookie if exists
        self.session
        page_header = html_header.format(title=title)
        return page_header + doc + f"""
        <hr>
        <code>msg = {self._msg}</code><br>
        <code>whoami = {self.username}</code><br>
        <code>{config.version_info}</code><br>
        <hr>
        </body>
        </html>
        """

    def raw_respond(self, response_code, body=b''):
        self._start_response(f'{response_code.value} {response_code.phrase}',
                             self.headers)
        return [body]

    def respond(self, response_document, title=None):
        if title is None:
            title = 'KDLP'
        self.headers += [('Content-Type', 'text/html')]
        response_document = self.format_html(response_document, title)
        return self.raw_respond(HTTPStatus.OK, response_document.encode())


def mk_form_welcome(session):
    return f'''
    <div class="logout_info">
        <div class="logout_left">
            <table>
                <tr><th>Cookie Key</th><th>Value</th></tr>
                <tr><td>Token</td><td>{session.token}</td></tr>
                <tr><td>User</td><td>{session.username}</td></tr>
                <tr><td>Expiry</td><td>{session.expiry_fmt()}</td></tr>
            </table>
        </div>
        <div class="logout_right">
            <h5> Welcome!</h5>
         </div>
    </div>
    <div class="logout_buttons">
        <form id="logout">
            <input class="logout" type="button" onclick="location.href='/logout';" value="Logout" />
        </form>
    </div>'''


def login_form(target_location=None):
    if target_location is not None:
        target_redir = f'?target={target_location}'
    else:
        target_redir = ''
    return f'''
    <form id="login" method="post" action="/login{target_redir}">
        <label for="username">Username:<br /></label>
        <input name="username" type="text" id="username" />
    <br />
        <label for="password">Password:<br /></label>
        <input name="password" type="password" id="password" />
    <br />
        <button type="submit">Submit</button>
    </form>
    <h3>Need an account? Register <a href="/register">here</a></h3><br>'''


def handle_login(rocket):
    target = rocket.queries_query('target')

    # harden the redirect to prevent csrf type attacks
    scheme, netloc, *_ = urlparse(target)
    if scheme or netloc:
        return rocket.raw_respond(HTTPStatus.BAD_REQUEST)

    def respond(welcome):
        if target and welcome:
            rocket.headers += [('Location', target)]
            return rocket.raw_respond(HTTPStatus.SEE_OTHER)
        elif target:
            return rocket.respond(login_form(target_location=target), 'Login')
        elif welcome:
            return rocket.respond(mk_form_welcome(rocket.session), 'Welcome')
        else:
            return rocket.respond(login_form(), 'Login')

    if rocket.session:
        rocket.msg(f'{rocket.username} authenticated by token')
        return respond(welcome=True)
    if rocket.method != 'POST':
        rocket.msg('welcome, please login')
        return respond(welcome=False)
    if not rocket.launch():
        rocket.msg('authentication failure')
        return respond(welcome=False)
    rocket.msg(f'{rocket.username} authenticated by password')
    return respond(welcome=True)


def handle_mail_auth(rocket):
    # This should be invariant when ngninx is configured properly
    mail_env_vars = ('HTTP_AUTH_USER', 'HTTP_AUTH_PASS',
                     'HTTP_AUTH_PROTOCOL', 'HTTP_AUTH_METHOD')
    [username, password, protocol, method] = [rocket.env.get(key)
                                              for key in mail_env_vars]

    if not username or not password \
            or protocol not in ('smtp', 'pop3') \
            or method != 'plain':
        return rocket.raw_respond(HTTPStatus.BAD_REQUEST)

    if not check_credentials(username, password):
        return rocket.raw_respond(HTTPStatus.UNAUTHORIZED)

    return rocket.raw_respond(HTTPStatus.OK)


def handle_logout(rocket):
    if rocket.session:
        rocket.retire()
    rocket.headers += [('Location', '/login')]
    return rocket.raw_respond(HTTPStatus.FOUND)


def handle_stub(rocket, more=[]):
    meth_path = f'{rocket.method} {rocket.path_info}'
    content = f'<h3>Development stub for {meth_path} </h3>{"".join(more)}'
    rocket.msg('oops')
    return rocket.respond(content)


def handle_activity(rocket):
    if not rocket.session:
        return rocket.raw_respond(HTTPStatus.FORBIDDEN)

    submissions = (mailman.db.Submission.select()
                   .where(mailman.db.Submission.user == rocket.session.username)
                   .order_by(- mailman.db.Submission.timestamp))

    def submission_fields(sub):
        return (datetime.fromtimestamp(sub.timestamp).astimezone().isoformat(),
                sub.recipient, sub.email_count, sub.in_reply_to or '-',
                sub.submission_id, sub.status or '-')

    # Split data from Submission table into values for HTML table
    table_data = [[f'<td>{val}</td>' for val in submission_fields(sub)]
                  for sub in submissions]
    table_content = '</tr>\n<tr>'.join(''.join(row) for row in table_data)

    return rocket.respond(f"""
    <table>
    <tr>
      <th>Timestamp</th>
      <th>Recipient</th>
      <th>Email Count</th>
      <th>In Reply To</th>
      <th>Submission ID</th>
      <th>Status</th>
    </tr>
    <tr>{table_content}</tr>
    </table>
    """, "Activity Log")


class OopsStatus:
    PAST_DUE = 0
    AVAILABLE = 1
    USED_HERE = 2
    UNAVAILABLE = 3


class AsmtTable:
    def __init__(self, assignment, oopsieness, peer1, peer2, init,
                 review1, review2, final):
        self.assignment = assignment
        self.name = assignment.name
        self.oopsieness = oopsieness
        self.peer1 = peer1
        self.peer2 = peer2
        self.init = init
        self.review1 = review1
        self.review2 = review2
        self.final = final

    def oops_button_hover(self):
        match self.oopsieness:
            case OopsStatus.PAST_DUE:
                return (f"Too late to oopsie! {self.name} "
                        "initial submission is past due!")
            case OopsStatus.AVAILABLE:
                return f"Click to use your oopsie on {self.name}"
            case OopsStatus.USED_HERE:
                return "Oopsie used here!"
            case OopsStatus.UNAVAILABLE:
                return "You have already used your oopsie"

    def gradeable_row(self, item_name, gradeable, rightmost_col):
        return f"""
        <tr>
          <th>
            {item_name}
          </th>
          <td>
            {datetime.fromtimestamp(gradeable.timestamp).astimezone().isoformat() if gradeable else '-'}
          </td>
          <td>
            {gradeable.submission_id if gradeable else '-'}
          </td>
          <th>
            {rightmost_col}
          </th>
        </tr>
        """

    def oopsie_button(self):
        return f"""
        <button {'disabled' if self.oopsieness != OopsStatus.AVAILABLE else ''}
         title='{self.oops_button_hover()}' type="submit" name="oopsie"
         value="{self.name}">
           Oopsie!
         </button>
        """

    def body(self):
        if self.oopsieness == OopsStatus.USED_HERE:
            return f"""
              {self.gradeable_row('Final Submission', self.final, self.oopsie_button())}
              <tr>
                <th>Comments</th>
                <td colspan="3">-</td>
              </tr>
            """
        if (not self.init or
            (int(datetime.now().timestamp())
             < self.assignment.initial_due_date)):
            return f"""
              {self.gradeable_row('Initial Submission', self.init, self.oopsie_button())}
              <tr>
                <th>Automated Feedback</th>
                <td colspan="3">-</td>
              </tr>
            """
        return f"""
          {self.gradeable_row('Initial Submission', self.init, self.oopsie_button())}
          <tr>
            <th>Automated Feedback</th>
            <td colspan="3">-</td>
          </tr>
          <tr>
            <th></th>
            <th>Timestamp</th>
            <th>Submission ID</th>
            <th>Score</th>
          </tr>
          {self.gradeable_row(self.peer1 + ' Peer Review', self.review1, '-') if self.peer1 else ''}
          {self.gradeable_row(self.peer2 + ' Peer Review', self.review2, '-') if self.peer2 else ''}
          {self.gradeable_row('Final Submission', self.final, '-')}
          <tr>
            <th>Comments</th>
            <td colspan="3">-</td>
          </tr>
        """

    def __str__(self):
        return f"""
        <table>
          <caption><h3>{self.name}</h3></caption>
          <tr>
            <th>Total Score: -</th>
            <th>Timestamp</th>
            <th>Submission ID</th>
            <th>Request an 'Oopsie'</th>
          </tr>
          {self.body()}
        </table>
        <br>
        """


def get_asmt_oopsieness(oops, cur_assignment, initial_due):
    if oops and oops.assignment == cur_assignment:
        return OopsStatus.USED_HERE
    if initial_due < int(datetime.now().timestamp()):
        return OopsStatus.PAST_DUE
    if oops:
        return OopsStatus.UNAVAILABLE
    return OopsStatus.AVAILABLE


def handle_dashboard(rocket):
    if not rocket.session:
        return rocket.raw_respond(HTTPStatus.FORBIDDEN)
    asmt_tbl = denis.db.Assignment
    if rocket.method != 'GET':
        if not (asn := rocket.body_args_query('oopsie')):
            return rocket.raw_respond(HTTPStatus.BAD_REQUEST)
        if not (asn_entry := asmt_tbl.get_or_none(asmt_tbl.name == asn)):
            return rocket.raw_respond(HTTPStatus.BAD_REQUEST)
        if (now := datetime.now().timestamp()) > asn_entry.initial_due_date:
            return rocket.raw_respond(HTTPStatus.BAD_REQUEST)
        if not rocket.body_args_query('confirm'):
            return rocket.respond(f'''
                <h2>Are you sure?</h2>
                <p>You get only one oopsie during the whole semester.
                Are you sure that you want to use it on {asn}?</p>
                <form method="post" action="/dashboard">
                <input type="hidden" name="oopsie" value="{asn}">
                <button type="submit" formmethod="get">Cancel</button>
                <button type="submit" name="confirm" value="y">Confirm</button>
                <br><br>
                </form>
            ''', 'Are you sure?')
        try:
            db.Oopsie.create(user=rocket.session.username, assignment=asn,
                             timestamp=int(now))
        except db.peewee.IntegrityError:
            return rocket.raw_respond(HTTPStatus.BAD_REQUEST)
    oops_tbl = db.Oopsie
    oops = oops_tbl.get_or_none(oops_tbl.user == rocket.session.username)
    peer_tbl = denis.db.PeerReviewAssignment
    peer_asns = (peer_tbl.select()
                         .where(peer_tbl.reviewer == rocket.session.username))
    grd_tbl = mailman.db.Gradeable
    user_gradeables = (grd_tbl.select()
                       .where(grd_tbl.user == rocket.session.username)
                       .order_by(grd_tbl.timestamp.desc()))
    assignments = asmt_tbl.select().order_by(asmt_tbl.initial_due_date)
    ret = '<form method="post" action="/dashboard">'
    for assignment in assignments:
        oopsieness = get_asmt_oopsieness(oops, assignment.name,
                                         assignment.initial_due_date)
        peers = (peer_asns.where(peer_tbl.assignment == assignment.name)
                          .first())
        peer1 = peers.reviewee1 if peers else None
        peer2 = peers.reviewee2 if peers else None
        asn_gradeables = (user_gradeables
                          .where(grd_tbl.assignment == assignment.name))
        init = asn_gradeables.where(grd_tbl.component == 'initial').first()
        rev1 = asn_gradeables.where(grd_tbl.component == 'review1').first()
        rev2 = asn_gradeables.where(grd_tbl.component == 'review2').first()
        final = asn_gradeables.where(grd_tbl.component == 'final').first()
        ret += str(AsmtTable(assignment, oopsieness, peer1, peer2, init, rev1,
                             rev2, final))
    return rocket.respond(ret + '</form>', 'Dashboard')


def find_creds_for_registration(student_id):
    password = secrets.token_urlsafe(nbytes=config.num_bytes_entropy_for_pw)
    salt = bcrypt.gensalt()
    pwdhash = bcrypt.hashpw(password.encode(), salt).decode()

    query = (db.User
             .update({db.User.pwdhash: pwdhash})
             .where((db.User.student_id == student_id) &
                    db.User.pwdhash.is_null())
             .returning(db.User))
    if (user := next(iter(query.execute()), None)):
        return user.username, password

    return None


def handle_register(rocket):
    def form_respond():
        return rocket.respond('''
    <form id="register" method="post" action="/register">
        <label for="student_id">Student ID:</label>
        <input name="student_id" type="text" id="student_id" /><br />
        <button type="submit">Submit</button>
    </form>''', 'Register')

    if rocket.method != 'POST':
        return form_respond()
    if not (student_id := rocket.body_args_query('student_id')):
        rocket.msg('you must provide a student id')
        return form_respond()
    if not (creds := find_creds_for_registration(student_id)):
        rocket.msg('no such student')
        return form_respond()
    username, password = creds
    rocket.msg('welcome to the classroom')
    return rocket.respond(f'''
    <h1>Save these credentials, you will not be able to access them again</h1><br>
    <h3>Username: {username}</h3><br>
    <h3>Password: {password}</h3><br>''', 'Welcome to the classroom')


def extract_basic_auth(rocket):
    if (auth_str := rocket.env.get('HTTP_AUTHORIZATION')) is None:
        return
    if not auth_str.startswith('Basic '):
        return
    cred_str = base64.b64decode(auth_str.removeprefix('Basic '))
    username, password = cred_str.decode().split(':', maxsplit=1)

    return username, password


def determine_cache_entry(cred_str):
    import hashlib
    import time
    hasher = hashlib.sha256()
    hasher.update(cred_str)
    hasher.update(str(int(time.time())).encode())
    return hasher.digest()


def http_basic_auth(rocket):
    import authcache
    if not (creds := extract_basic_auth(rocket)):
        return
    username, password = creds
    cache_entry = determine_cache_entry((':'.join(creds)).encode())
    if authcache.entry_exists(cache_entry):
        return True
    if not check_credentials(username, password):
        return
    authcache.add_entry(cache_entry)
    return True


def handle_cgit(rocket):
    if not rocket.session:
        if (not (agent := rocket.env.get('HTTP_USER_AGENT'))
           or not agent.startswith('git/')):
            return rocket.raw_respond(HTTPStatus.FORBIDDEN)
        if not http_basic_auth(rocket):
            rocket.headers.append(('WWW-Authenticate', 'Basic realm="cgit"'))
            return rocket.raw_respond(HTTPStatus.UNAUTHORIZED)
    cgit_env = os.environ.copy()
    cgit_env['PATH_INFO'] = rocket.path_info.removeprefix('/cgit')
    cgit_env['QUERY_STRING'] = rocket.env.get('QUERY_STRING', '')

    def cgit_internal_server_error(msg):
        print(f'cgit: Error {msg} at path_info "{cgit_env["PATH_INFO"]}"'
              f' and query string "{cgit_env["QUERY_STRING"]}"',
              file=sys.stderr)
        return rocket.raw_respond(HTTPStatus.INTERNAL_SERVER_ERROR)

    proc = subprocess.Popen(['/usr/share/webapps/cgit/cgit'],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            env=cgit_env)
    so, se = proc.communicate()
    try:
        raw_headers, raw_body = so.split(b'\n\n', maxsplit=1)
        headers_text = raw_headers.decode()
        headers = [tuple(line.split(': ', maxsplit=1))
                   for line in headers_text.split('\n')]
        raw_return = False
        status = HTTPStatus.OK
        if headers[0][0] == 'Status':
            status_str = headers[0][1]
            status = HTTPStatus(int(status_str.split(' ')[0]))
            if status == HTTPStatus.OK:
                return cgit_internal_server_error('Unexpected 200 status')
            raw_return = True
            raw_body = b''
            del headers[0]
        if headers[0][0] != 'Content-Type':
            return cgit_internal_server_error('missing Content-Type')
        if headers[0][1] != 'text/html; charset=UTF-8':
            raw_return = True
        rocket.headers += headers
        if raw_return:
            return rocket.raw_respond(status, raw_body)
        outstring = raw_body.decode()
        return rocket.respond(outstring, 'CGit')  # TODO: get real title? (file issue upstream)
    except (UnicodeDecodeError, ValueError, IndexError) as ex:
        return cgit_internal_server_error(type(ex))


def handle_containerfile(rocket):
    nano_default_editor = 'nano-default-editor' \
            if not rocket.queries_query('vim') else ''

    hostname = os.getenv("HOSTNAME")
    if creds := extract_basic_auth(rocket):
        username, password = creds
    if not creds or not check_credentials(username, password):
        rocket.headers.append(('WWW-Authenticate', 'Basic realm="podman"'))
        return rocket.raw_respond(HTTPStatus.UNAUTHORIZED)
    tbl = db.User
    if (not (user := tbl.get_or_none(tbl.username == username)) or
            not (fullname := user.fullname)):
        fullname = 'Unknown'
    return rocket.raw_respond(HTTPStatus.OK, rf'''
FROM fedora:41

RUN <<DNF
dnf -y update
dnf install -y --setopt=install_weak_deps=False \
git \
tar \
make \
gcc \
qemu-system-riscv \
qemu-user-static-riscv \
binutils-riscv64-linux-gnu \
gcc-riscv64-linux-gnu \
bc \
flex \
bison \
openssl-devel \
elfutils-libelf-devel \
ncurses-devel \
dwarves \
git-email \
vim \
nano \
{nano_default_editor} \
mutt \
cpio \
wget \
cyrus-sasl-plain \
gdb \
diffutils \
strace \
man \
man-pages \
;
dnf clean all
DNF

RUN useradd {username} -U
USER {username}:{username}
WORKDIR /home/{username}/

RUN mkdir .cache

RUN cat <<'MUTTRC' > ~/.muttrc
set realname="{fullname}"
set my_username="{username}"
set my_password="{password}"
set my_course_domain="{hostname}"
set spoolfile=
set record=
set folder=
set sort=threads
set from="$my_username@$my_course_domain"
set header_cache=~/.cache/mutt
set smtp_url="smtps://$my_username:$my_password@$my_course_domain:465"
push "<change-folder>pops://$my_username:$my_password@$my_course_domain:995"\n
macro index l "|git am -s"\n
MUTTRC

RUN cat <<'GITCONFIG' > ~/.gitconfig
[user]
name = '{fullname}'
email = {username}@{hostname}
[sendemail]
smtpUser = {username}
smtpPass = {password}
smtpserver = {hostname}
smtpserverport = 465
smtpencryption = ssl
GITCONFIG

VOLUME /home

ENTRYPOINT ["/usr/bin/bash", "-l", "-i"]
'''.encode())


def handle_error(rocket):
    error_num_str = rocket.queries_query('num')
    try:
        error_num = int(error_num_str)
        error = HTTPStatus(error_num)
    except ValueError as e:
        print(f'invalid query passed to handle error {e}', file=sys.stderr)
        return rocket.raw_respond(HTTPStatus.INTERNAL_SERVER_ERROR)
    error_description = (f'<h1>HTTP ERROR {error.value}: '
                         f'{error.name.upper().replace("_", " ")}</h1>')
    return rocket.respond(error_description, f'ERROR {error.value}')


def handle_try_md(rocket):
    if not rocket.path_info.endswith('.md'):
        return rocket.raw_respond(HTTPStatus.NOT_FOUND)
    path = f'{config.doc_root}{rocket.path_info}'
    if not os.access(path, os.R_OK):
        return rocket.raw_respond(HTTPStatus.NOT_FOUND)
    with open(path) as file:
        md = file.read()
    html = markdown.markdown(md, extensions=['tables', 'fenced_code',
                                             'footnotes', 'toc'])
    # Use the first line of the document as the title, sans #
    if (title_end := md.find('\n')) != -1:
        title = md[0:title_end].lstrip('#').strip()
    else:
        title = 'KDLP'
    return rocket.respond(html, title)


def application(env, SR):
    rocket = Rocket(env, SR)
    if rocket.method != 'GET' and rocket.method != 'POST':
        return rocket.raw_respond(HTTPStatus.METHOD_NOT_ALLOWED)

    # routes supporting get and post
    match rocket.path_info:
        case '/login':
            return handle_login(rocket)
        case '/register':
            return handle_register(rocket)
        case '/dashboard':
            return handle_dashboard(rocket)
        case _:
            if rocket.method != 'GET':
                return rocket.raw_respond(HTTPStatus.METHOD_NOT_ALLOWED)

    # routes supporting only get
    match rocket.path_info:
        case '/logout':
            return handle_logout(rocket)
        case '/mail_auth':
            return handle_mail_auth(rocket)
        case '/Containerfile':
            return handle_containerfile(rocket)
        case '/activity':
            return handle_activity(rocket)
        case '/error':
            return handle_error(rocket)
        case p:
            if p.startswith('/cgit'):
                return handle_cgit(rocket)
            else:
                return handle_try_md(rocket)
