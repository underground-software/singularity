#!/usr/bin/env python3

import datetime
import signal
import subprocess
import sys

import db

from configure import far_future


def spawn_waiter(timestamp, name, script):
    return subprocess.Popen(['/usr/local/bin/run-at', timestamp, script, name])


def in_the_future(ts):
    return datetime.datetime.now() < datetime.datetime.fromtimestamp(ts)


def handle_trigger(info):
    if info.si_code != -1:
        print('spurious sigrtmin without queuing info!', file=sys.stderr)
        return False
    assignment_id, component_id = divmod(info.si_status, 3)
    if not (asn := db.Assignment.get_or_none(db.Assignment.id == assignment_id)):
        print(f'trigger for non existant assignment id {assignment_id}!', file=sys.stderr)
        return
    match component_id:
        case 0:
            component = 'initial submission'
            attr = 'initial_due_date'
            program = './initial.py'
        case 1:
            component = 'peer review'
            attr = 'peer_review_due_date'
            program = './peer_review.py'
        case 2:
            component = 'final submission'
            attr = 'final_due_date'
            program = './final.py'
        case _:
            print(f'invalid component id {component_id}!', file=sys.stderr)
            return
    if not in_the_future(getattr(asn, attr)):
        print(f'{component} for {asn.name} already passed!', file=sys.stderr)
        return

    # update relevant deadline to current time so that dashboard etc behaves as expected
    setattr(asn, attr, int(datetime.datetime.now().timestamp()))
    asn.save()
    subprocess.Popen([program, asn.name]).wait()


def main():
    # this handler function should never actually run,
    # but because we are pid 1 in container we need
    # to register handlers or signals wont be delivered
    def signal_handler(*_):
        assert False
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGUSR1, signal_handler)
    signal.signal(signal.SIGRTMIN, signal_handler)

    again = True
    while again:
        procs = []
        for assignment in db.Assignment.select():
            name = assignment.name
            initial = assignment.initial_due_date
            peer_review = assignment.peer_review_due_date
            final = assignment.final_due_date

            if initial == far_future:
                pass
            elif in_the_future(initial):
                procs.append(spawn_waiter(str(initial), name, './initial.py'))
            else:
                print(f'skipping initial for {name}', file=sys.stderr)

            if peer_review == far_future:
                pass
            elif in_the_future(peer_review):
                procs.append(spawn_waiter(str(peer_review), name, './peer_review.py'))
            else:
                print(f'skipping peer review for {name}', file=sys.stderr)

            if final == far_future:
                pass
            elif in_the_future(final):
                procs.append(spawn_waiter(str(final), name, './final.py'))
            else:
                print(f'skipping final for {name}', file=sys.stderr)

        while True:
            # send SIGUSR1 to reload with new due dates, SIGTERM to exit, SIGRTMIN to trigger a deadline
            info = signal.sigwaitinfo([signal.SIGUSR1, signal.SIGTERM, signal.SIGRTMIN])
            match info.si_signo:
                case signal.SIGUSR1:
                    print('reloading', file=sys.stderr)
                case signal.SIGTERM:
                    again = False
                case signal.SIGRTMIN:
                    handle_trigger(info)
                    # no need to reload
                    continue
            break

        for proc in procs:
            proc.terminate()


if __name__ == '__main__':
    exit(main())
