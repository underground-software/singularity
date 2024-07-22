#!/usr/bin/env python3

import datetime
import signal
import subprocess
import sys

import db


def spawn_waiter(timestamp, name, script):
    return subprocess.Popen(['/usr/local/bin/run-at', timestamp, script, name])


def in_the_future(ts):
    return datetime.datetime.now() < datetime.datetime.fromtimestamp(ts)


def main():
    # neither of these handlers should actually run,
    # but because we are pid 1 in container we need
    # to register handlers or they wont be delivered
    def signal_handler(*_):
        assert False
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGUSR1, signal_handler)

    again = True
    while again:
        procs = []
        for assignment in db.Assignment.select():
            name = assignment.name
            initial = assignment.initial_due_date
            final = assignment.final_due_date

            if in_the_future(initial):
                procs.append(spawn_waiter(str(initial), name, './initial.py'))
            else:
                print(f'skipping initial for {name}', file=sys.stderr)

            if in_the_future(final):
                procs.append(spawn_waiter(str(final), name, './final.py'))
            else:
                print(f'skipping final for {name}', file=sys.stderr)

        # send SIGUSR1 to reload with new due dates, SIGTERM to exit
        if signal.SIGUSR1 == signal.sigwait([signal.SIGUSR1, signal.SIGTERM]):
            print('reloading', file=sys.stderr)
        else:
            again = False

        for proc in procs:
            proc.terminate()


if __name__ == '__main__':
    exit(main())
