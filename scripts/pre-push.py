#!/usr/bin/env python3
"""Type check each outgoing commit snapshot, independently of working-tree edits."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def main():
    checked = set()
    for line in sys.stdin:
        fields = line.split()
        if len(fields) != 4:
            raise ValueError('Expected four fields from Git pre-push')
        local_ref, local_oid, _, remote_oid = fields
        if set(local_oid) == {'0'} or local_oid == remote_oid:
            continue
        commit = git('rev-parse', '--verify', local_oid + '^{commit}')
        if commit in checked:
            continue
        print(f'Type checking {local_ref} ({commit[:12]})', flush=True)
        with tempfile.TemporaryDirectory(prefix='jobsdone-pre-push-') as temporary:
            directory = Path(temporary)
            archive = directory / 'source.tar'
            snapshot = directory / 'source'
            snapshot.mkdir()
            subprocess.run(['git', '-C', str(ROOT), 'archive', '--format=tar',
                            '--output=' + str(archive), commit], check=True)
            subprocess.run(['tar', '-xf', str(archive), '-C', str(snapshot)], check=True)
            env = dict(os.environ)
            for name in git('rev-parse', '--local-env-vars').splitlines():
                env.pop(name, None)
            subprocess.run(['./scripts/typecheck.sh'], cwd=snapshot, env=env, check=True)
        checked.add(commit)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'Pre-push type checking failed: {error}') from error
