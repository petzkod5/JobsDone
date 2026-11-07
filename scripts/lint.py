#!/usr/bin/env python3
"""Lint every Git-visible Swift file, or the complete staged snapshot."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = "0.65.1"


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args])


def lint(root, binary, cache, paths):
    for name in paths:
        path = root / name
        if path.name in (".swiftlint.yml", ".swiftlint.yaml") and name != ".swiftlint.yml":
            raise ValueError(f"Nested SwiftLint configuration is forbidden: {name}")
        if not name.endswith(".swift"):
            continue
        if path.is_symlink():
            raise ValueError(f"Swift source symlinks are forbidden: {name}")
        if not path.is_file():
            raise ValueError(f"Missing Swift source: {name}; stage its deletion first")
        if re.search(r"swiftlint\s*:", path.read_text()):
            raise ValueError(f"Inline SwiftLint directives are forbidden: {name}")
    files = [str(root / name) for name in paths if name.endswith(".swift")]
    if not files:
        raise ValueError("No Swift files found")
    return subprocess.call([str(binary), "lint", "--strict", "--disable-sourcekit",
                            "--config", str(root / ".swiftlint.yml"),
                            "--cache-path", str(cache), "--quiet", *files], cwd=root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true")
    args = parser.parse_args()
    binary = ROOT / ".local/tools/swiftlint/swiftlint"
    if not binary.is_file():
        raise ValueError("Missing SwiftLint. Run ./scripts/setup-lint.sh")
    if subprocess.check_output([str(binary), "version"], text=True).strip() != VERSION:
        raise ValueError(f"Use SwiftLint {VERSION}; run ./scripts/setup-lint.sh")
    cache = ROOT / ".local/cache/swiftlint"
    if args.staged:
        paths = git("ls-files", "-z").decode().split("\0")[:-1]
        with tempfile.TemporaryDirectory(prefix="jobsdone-index-") as temporary:
            subprocess.run(["git", "-C", str(ROOT), "checkout-index", "--all",
                            "--prefix", temporary + os.sep], check=True)
            return lint(Path(temporary), binary, cache, paths)
    paths = sorted(set(git("ls-files", "--cached", "--others", "--exclude-standard", "-z")
                       .decode().split("\0")[:-1]))
    return lint(ROOT, binary, cache, paths)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"Swift lint failed: {error}") from error
