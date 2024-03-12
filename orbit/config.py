#!/usr/bin/env python3

# TODO some can be generated at container build time

srvname = 'kdlp.underground.software'
production = False

appname = 'orbit'
version = '0.1'
source = 'https://github.com/underground-software/orbit'

radius_port = '9098'

smtp_port_dfl = '11465'
smtp_port_lfx = '11465'
smtp_port_ext = '465'

pop3_port_dfl = '11995'
pop3_port_lfx = '11995'
pop3_port_ext = '995'

matrix_port = '8448'

# read these documents from a filesystem path
orbit_root = '/orbit'
doc_root = f'{orbit_root}/docs'
doc_header = f'{orbit_root}/header.html'
database = f'{orbit_root}/orbit.db'

email_dir = f'{orbit_root}/email'

# duration of authentication token validity period
minutes_each_session_token_is_valid = 180

sql_verbose = False

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("Pass config var name as argument", file=sys.stderr)
        sys.exit(1)
    else:
        print(locals()[sys.argv[1]])
