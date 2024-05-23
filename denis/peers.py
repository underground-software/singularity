#!/bin/env python
#
# ata.peer.py: Generate two unique peer review assignments for each stuent from a list of students

import random, datetime, sys, os
# make sure each student has exactly two non-self, non-equal peers

err = lambda msg: print(msg, file=sys.stderr)

# precondition: 3 or more lines in stdin
def test_peers(stud_map):
    base_err = 'invalid peer mapping:'
    peer_cnt = {stud: 0 for stud in stud_map}
    for k in stud_map:
        # validate no self peers
        if k in stud_map[k]:
            err(f'{base_err} {k} to self')
            return False
        # validate no duplicate peers
        if v := stud_map[k]:
            if v[0] == v[1]:
                err(f'{base_err} duplicate {v}')
                return False
            # track per-user peer count
            peer_cnt[v[0]] += 1
            peer_cnt[v[1]] += 1
    # Validate all students have two peers
    if all([peer_cnt[s] == 2 for s in peer_cnt]):
        return True
    else:
        err(f'{base_err} peer imbalance {peer_cnt}')
        return False

def generate_cycle(studs):
    without = lambda x, y: list(filter(lambda z: z not in x, y))
    random.seed(datetime.datetime.now(datetime.UTC).timestamp())
    cycle = []
    while available := without(cycle, stud_list):
        cycle += random.choices(available)
    return cycle

def nextify_cycle(cycle):
    random.seed(datetime.datetime.now(datetime.UTC).timestamp())
    return [cycle[(i + 1) % len(cycle)] for i in range(len(cycle))]

stud_list = [l.strip() for l in sys.stdin]

match len(stud_list):
    case 0:
        exit(0)
    case 1:
        print(stud_list[0])
        exit(0)
    case 2:
        print(f'{stud_list[0]}\t{stud_list[1]}\n{stud_list[1]}\t{stud_list[0]}')
        exit(0)
        
stud_map = {stud: [] for stud in sys.stdin}

base_cycle = generate_cycle(stud_list)
first = nextify_cycle(base_cycle)
second = nextify_cycle(first)

for i, k in enumerate(base_cycle):
    stud_map[k] = (first[i], second[i])

if not test_peers(stud_map):
    exit(1)
else:
    print('\n'.join([f'{k}\t{v[0]}\t{v[1]}' for k,v in stud_map.items()]))
    exit(0)
