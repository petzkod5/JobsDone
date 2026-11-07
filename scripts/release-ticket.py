#!/usr/bin/env python3
"""Retry transient Apple ticket-service failures without rebuilding the app."""
import argparse
import subprocess
import sys
import time


def run_stapler(operation, app):
    delays = (30, 60)
    for attempt in range(len(delays) + 1):
        try:
            result = subprocess.run(['xcrun', 'stapler', operation, str(app)], timeout=120)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 124
        if code == 0:
            return 0
        if code not in (65, 68, 124) or attempt == len(delays):
            print(f'Stapler {operation} failed (exit {code}); release stopped.', file=sys.stderr)
            return code
        delay = delays[attempt]
        print(f'Stapler {operation} failed (exit {code}); retrying in {delay}s.', file=sys.stderr, flush=True)
        time.sleep(delay)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('staple', 'validate'))
    parser.add_argument('app')
    args = parser.parse_args()
    sys.exit(run_stapler(args.operation, args.app))
