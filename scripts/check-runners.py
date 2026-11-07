#!/usr/bin/env python3
"""Require every macOS workflow job to use one pinned runner label.

PR checks must compile with the same Swift toolchain as the release package job.
A floating label such as macos-latest, or a release job on a different image,
lets the release compiler differ from the one that validated the merged source.
"""
from pathlib import Path
import re
import sys

RUNS_ON = re.compile(r'^\s*runs-on:(.*)$')


def runner_errors(workflow_dir):
    errors, labels = [], {}
    files = sorted([*Path(workflow_dir).glob('*.yml'), *Path(workflow_dir).glob('*.yaml')])
    for path in files:
        for number, line in enumerate(path.read_text().splitlines(), 1):
            match = RUNS_ON.match(line)
            if not match:
                continue
            where = f'{path.name}:{number}'
            label = match.group(1).split('#', 1)[0].strip().strip('\'"')
            # Expressions, lists, and mappings could hide a macOS label; fail closed.
            if not re.fullmatch(r'[A-Za-z0-9._-]+', label):
                errors.append(f'{where}: runs-on must be one literal runner label, not {label or "a block"!r}')
            elif label.startswith('macos'):
                if label.endswith('-latest'):
                    errors.append(f'{where}: pin a macOS version instead of {label}')
                labels.setdefault(label, []).append(where)
    if len(labels) > 1:
        detail = '; '.join(f'{label} at {", ".join(places)}' for label, places in sorted(labels.items()))
        errors.append(f'macOS jobs must share one runner label so CI and releases use one Swift toolchain: {detail}')
    return errors


def main():
    workflow_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / '.github/workflows'
    errors = runner_errors(workflow_dir)
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
