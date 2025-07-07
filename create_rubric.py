#!/bin/env python

from argparse import ArgumentParser as ap
import git
import os


def main():
    parser = ap(prog='create_rubric', description='create rubric')
    parser.add_argument('-n', type=int, help='number of patches to examine',
                        required=True)

    args = parser.parse_args()

    repo = git.Repo(os.getcwd())
    for i in range(args.n):
        patch = repo.git.execute(['git', 'show', f'HEAD~{args.n-i-1}'])
        changelines = list(filter(lambda line: line.startswith('--- ') or line.startswith('+++ '), patch.split('\n')))
        changeline_pairs = {(fromfile, tofile): 0 for fromfile, tofile in zip(changelines[::2], changelines[1::2])}
        print(f'{"[" if i == 0 else ""}{changeline_pairs}{"," if i < args.n - 1 else "]"}')


if __name__ == '__main__':
    main()
