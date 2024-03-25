#!/usr/bin/env python3
import json
import time
import config
import subprocess
import argparse
from datetime import datetime
from dataclasses import dataclass
from pprint import pprint
from typing import Self


def sleep_until(target: float):
    now = time.time()
    while target - now > 0.5:
        time.sleep((target - now) * 0.5)
        now = time.time()


def parse_date_to_unix(date: str):
    result = subprocess.run(
        ["date", "-d", date, "+%s"], capture_output=True)
    if result.returncode != 0:
        raise Exception(result.stderr.decode("utf-8"))
    return int(result.stdout)


@dataclass
class Assignment:
    web_id: str
    email_id: str
    due: datetime

    def from_json(row: dict) -> Self:
        due = datetime.fromtimestamp(parse_date_to_unix(row["due"]))
        return Assignment(row["web_id"], row["email_id"], due)

    def due_date_passed(self) -> bool:
        return self.due < datetime.now()

    def due_date_as_unix(self) -> float:
        return self.due.astimezone().timestamp()


def load_assignments() -> list[Assignment]:
    with open(f"{config.orbit_root}/assignments.json", 'r') as f:
        json_data = json.load(f)
    return list(map(Assignment.from_json, json_data["assignments"]))


def trigger_due_date_passed(a: Assignment):
    print(a.web_id, "due date triggered")


if __name__ == "__main__":
    assignments = load_assignments()
    assignments = filter(lambda a: not a.due_date_passed(), assignments)
    assignments = sorted(assignments, key=lambda a: a.due)

    pprint(assignments)
    while len(assignments) > 0:
        a = assignments.pop(0)
        sleep_until(a.due_date_as_unix())
        trigger_due_date_passed(a)
