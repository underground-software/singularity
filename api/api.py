from config import version_info
from datetime import datetime
import json
import requests
from urllib.parse import parse_qs
import mailman.db


ORBIT_AUTH_URL = 'http://orbit:9098/login?json=yes'


def authenticate(body_args, queries):
    def get_or_none(b, query):
        q = b.get(query.encode(), [b''])[0]
        if q == b'':
            return None
        return q
    body = {}
    if (username := get_or_none(body_args, 'username')):
        body['username'] = username.decode()
    if (password := get_or_none(body_args, 'password')):
        body['password'] = password.decode()
    if (token := get_or_none(body_args, 'token')):
        body['token'] = token.decode()
    if not ((username and password) or token):
        return None
    response = requests.post(ORBIT_AUTH_URL, data=body)

    if response.status_code == 200:
        reply = response.json()
        if reply.get('authenticated', False):
            return reply.get('username', None)
    else:
        return None


def activity_log(username):
    submissions = (mailman.db.Submission.select()
                   .where(mailman.db.Submission.user == username)
                   .order_by(- mailman.db.Submission.timestamp))

    log = []
    if submissions:
        for s in submissions:
            log.append({
                'Timestamp': datetime.fromtimestamp(s.timestamp).astimezone().isoformat(),
                'Recipient': s.recipient,
                'Email Count': s.email_count,
                'In Reply To': s.in_reply_to or '-',
                'Submission ID': s.submission_id,
                'Status': s.status or '-'
            })

    return [json.dumps({'timestamp': datetime.now().astimezone().isoformat(),
                        'activity_log': log}).encode()]


def json_error(error):
    return json.dumps({'timestamp': datetime.now().astimezone().isoformat(),
                       'error': error}).encode()


def application(env, SR):
    headers = [('Content-Type', 'application/json')]
    SR('200 OK', headers)
    method = env.get('REQUEST_METHOD', "GET")
    content_length = int(env.get('CONTENT_LENGTH', "0"))
    if method == "POST":
        body_args = parse_qs(env['wsgi.input'].read(content_length))
    else:
        body_args = {}
    queries = parse_qs(env.get("QUERY_STRING", ""))
    do_authenticate = lambda: authenticate(body_args, queries)

    path_info = env.get("PATH_INFO", "/")
    match path_info.split('/'):
        case ['', 'api', 'version']:
            return [json.dumps({'version': version_info}).encode()]
        case ['', 'api', 'activity']:
            if (username := do_authenticate()):
                return activity_log(username)
            else:
                return json_error('invalid credentials')
        case _:
            return json_error('Invalid endpoint')
