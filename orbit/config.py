# TODO some can be generated at container build time

import os

production = os.environ.get("PRODUCTION") == "true"

appname = 'singularity'
version = '0.1'
source = 'https://github.com/underground-software/singularity'

smtp_port = '2465'
pop3_port = '2995'

# read these documents from a filesystem path
orbit_root = '/orbit'
doc_root = f'{orbit_root}/docs'
doc_header = f'{orbit_root}/header.html'
database = f'{orbit_root}/orbit.db'

# duration of authentication token validity period
minutes_each_session_token_is_valid = 180

sql_verbose = False
