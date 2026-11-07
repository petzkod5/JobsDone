#!/usr/bin/env python3
"""Validate the PR's complete commit range and its squash-merge title."""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

SUBJECT = re.compile(
    r"(?:feat|fix|perf|refactor|docs|style|test|build|ci|chore|revert)"
    r"(?:\([^()\r\n]+\))?!?: [^\s].*"
)
SHA = re.compile(r"[0-9a-f]{40}")


def errors(message):
    lines = message.splitlines()
    if not lines or not SUBJECT.fullmatch(lines[0]):
        return ["use type(scope): description, with an optional scope and !"]
    if len(lines) > 1 and lines[1].strip():
        return ["separate the subject and body with a blank line"]
    return []


def git(*args):
    return subprocess.check_output(["git", *args], text=True).rstrip("\n")


def check(pr, checkout):
    base, head = pr["base"]["sha"], pr["head"]["sha"]
    if not SHA.fullmatch(base) or not SHA.fullmatch(head):
        raise ValueError("PR metadata contains invalid commit IDs")
    if head != checkout:
        raise ValueError("PR head changed during the check; rerun on the latest commit")
    failures = []
    for error in errors(pr["title"]):
        failures.append("PR title: " + error)
    commits = git("rev-list", "--reverse", f"{base}..{head}").splitlines()
    if not commits:
        raise ValueError("PR commit range is empty")
    for commit in commits:
        message = git("show", "-s", "--format=%B", commit)
        for error in errors(message):
            failures.append(f"{commit[:12]}: {error}")
    return commits, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pull_request", type=Path, help="GitHub pull request API JSON")
    args = parser.parse_args()
    try:
        commits, failures = check(json.loads(args.pull_request.read_text()), git("rev-parse", "HEAD"))
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Cannot validate PR commits: {error}", file=sys.stderr)
        return 1
    if failures:
        print("Conventional Commit check failed:\n" + "\n".join(failures), file=sys.stderr)
        return 1
    print(f"Validated PR title and all {len(commits)} commits.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
