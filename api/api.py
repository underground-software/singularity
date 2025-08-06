def application(env, SR):
    headers = [('Content-Type', 'text/plain')]
    SR(f'200 OK', headers)
    return [b'API']
