from config import version_info
import json
from urllib.parse import parse_qs


def application(env, SR):
    headers = [('Content-Type', 'application/json')]
    SR('200 OK', headers)
    queries = parse_qs(env.get("QUERY_STRING", ""))
    path_info = env.get("PATH_INFO", "/")
    match path_info.split('/'):
        case ['', 'api', 'version']:
            return [json.dumps({'version': version_info}).encode()]
        case _:
            return [json.dumps({'error': 'Invalid endpoint'}).encode()]
