#!/usr/bin/env python3
"""Generate a cask from an already verified archive digest without downgrades."""
from pathlib import Path
import re
import sys

v, digest, repo, destination = sys.argv[1:]
def version(value):
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', value):
        raise SystemExit('Invalid stable version')
    return tuple(map(int, value.split('.')))
version(v)
if not re.fullmatch(r'[a-f0-9]{64}', digest) or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
    raise SystemExit('Invalid digest or repository')
target = Path(destination)
if target.exists():
    old = re.search(r'^  version "([^"]+)"$', target.read_text(), re.M)
    if not old:
        raise SystemExit('Cannot safely read existing cask version')
    if version(old[1]) > version(v):
        print('Tap already newer; skipping stale retry')
        sys.exit()
    if old[1] == v:
        old_sha = re.search(r'^  sha256 "([a-f0-9]{64})"$', target.read_text(), re.M)
        if not old_sha or old_sha[1] != digest:
            raise SystemExit('Same tap version has different checksum')
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(f'''cask "jobsdone" do
  version "{v}"
  sha256 "{digest}"

  url "https://github.com/{repo}/releases/download/v#{{version}}/JobsDone-#{{version}}-universal.zip"
  name "Job’s Done"
  desc "Menu bar monitor for GitHub pull requests"
  homepage "https://github.com/{repo}"

  depends_on formula: "gh"
  depends_on macos: ">= :ventura"

  app "Job’s Done.app"
end
''')
