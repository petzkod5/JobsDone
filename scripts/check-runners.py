#!/usr/bin/env python3
"""Require every macOS workflow job to use one pinned runner label.

PR checks must compile with the same Swift toolchain as the release package job.
A floating label such as macos-latest, or a release job on a different image,
lets the release compiler differ from the one that validated the merged source.
"""
from pathlib import Path
import re
import sys

# Block-style key, optionally quoted, with optional space before the colon.
RUNS_ON = re.compile(r'''^\s*(["']?)runs-on\1\s*:(.*)$''')


def workflow_files(paths):
    for path in map(Path, paths):
        if path.is_dir():
            yield from sorted([*path.glob('*.yml'), *path.glob('*.yaml')])
        else:
            yield path


def runner_errors(paths):
    errors, labels = [], {}
    for path in workflow_files(paths):
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if 'runs-on' not in line.split('#', 1)[0]:
                continue
            where = f'{path.name}:{number}'
            match = RUNS_ON.match(line)
            if not match:
                # Flow mappings or other syntax could hide a label from this line scan.
                errors.append(f'{where}: write runs-on as a block key with one literal label')
                continue
            # GitHub matches runner labels case-insensitively.
            label = match.group(2).split('#', 1)[0].strip().strip('\'"').lower()
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
    # check.sh passes tracked workflow files; a directory argument checks every workflow in it.
    paths = sys.argv[1:] or [Path(__file__).resolve().parents[1] / '.github/workflows']
    errors = runner_errors(paths)
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
