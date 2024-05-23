#!/bin/env python3

import sys
from peewee import fn

import db

def main():
    if len(sys.argv) < 2:
        print(f'usage: ./{sys.argv[0]} <assignment>')
        return 0

    assignment = sys.argv[1]

    submissions = (db.Submission.select()
                   .where(db.Submission.assignment == assignment)
                   .order_by(fn.Random()))

    students_detected = set()
    min_size = len("rejected:")
    for sub in submissions:
        if len(sub.status) >= min_size and sub.status[:min_size] != 'rejected:':
            students_detected.add(sub.user)

    print('\n'.join(students_detected))


if __name__ == "__main__":
    main()
