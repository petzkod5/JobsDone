#!/usr/bin/env python3
"""Release identity, immutable assets, and cask generation helpers (gh authenticated)."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def gh(*args):
    return run('gh', *args)


def api(path):
    return json.loads(gh('api', path))


def version(value):
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', value):
        raise SystemExit('Expected stable X.Y.Z version')
    return tuple(map(int, value.split('.')))


repo = os.environ['GITHUB_REPOSITORY']
mode = sys.argv[1]
tag = sys.argv[2]
if not tag.startswith('v'):
    raise SystemExit('Expected vX.Y.Z tag')
v = tag[1:]
version(v)
release = api(f'repos/{repo}/releases/tags/{tag}')
if release['tag_name'] != tag or release['prerelease']:
    raise SystemExit('Release identity mismatch')
run('git', 'fetch', '--no-tags', 'origin', f'refs/tags/{tag}', 'refs/heads/main')
remote_tag = gh('api', f'repos/{repo}/git/ref/tags/{tag}', '--jq', '.object.sha')
sha = run('git', 'rev-parse', remote_tag + '^{commit}')
main = gh('api', f'repos/{repo}/git/ref/heads/main', '--jq', '.object.sha')
run('git', 'merge-base', '--is-ancestor', sha, main)
if run('git', 'show', f'{sha}:version.txt') != v:
    raise SystemExit('Tag and committed version.txt differ')
manifest = json.loads(run('git', 'show', f'{sha}:.release-please-manifest.json'))
if manifest.get('.') != v:
    raise SystemExit('Tag and release manifest differ')
if mode == 'resolve':
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'tag={tag}\nsha={sha}\n')
    sys.exit()
if run('git', 'rev-parse', 'HEAD') != sha:
    raise SystemExit('Checked out source does not match immutable release tag')
asset = f'JobsDone-{v}-universal.zip'
folder = Path('dist/downloaded')
folder.mkdir(parents=True, exist_ok=True)
archive = folder / asset
assets = release['assets']
if sum(a['name'] == asset for a in assets) > 1:
    raise SystemExit('Duplicate release assets')
if mode == 'publish':
    if os.environ.get('MACOS_SIGNING_ENABLED') == 'true':
        for key in ('MACOS_CERTIFICATE_BASE64', 'MACOS_CERTIFICATE_PASSWORD', 'MACOS_SIGNING_IDENTITY',
                    'MACOS_NOTARY_KEY_BASE64', 'MACOS_NOTARY_KEY_ID', 'MACOS_NOTARY_ISSUER_ID'):
            if not os.environ.get(key):
                raise SystemExit(f'Signing enabled but {key} is missing')
    if any(a['name'] == asset for a in assets):
        gh('release', 'download', tag, '--repo', repo, '--pattern', asset, '--dir', str(folder), '--clobber')
    else:
        if not release['draft']:
            raise SystemExit('Refusing to add ZIP to an already published release')
        subprocess.run(['bash', 'scripts/release-package.sh'], check=True)
        gh('release', 'upload', tag, f'dist/release/{asset}', '--repo', repo)
        gh('release', 'download', tag, '--repo', repo, '--pattern', asset, '--dir', str(folder), '--clobber')
        if hashlib.sha256(archive.read_bytes()).digest() != hashlib.sha256(Path(f'dist/release/{asset}').read_bytes()).digest():
            raise SystemExit('Uploaded ZIP differs from built ZIP')
else:
    gh('release', 'download', tag, '--repo', repo, '--pattern', asset, '--dir', str(folder), '--clobber')
subprocess.run(['bash', 'scripts/release-validate.sh', str(archive), v], check=True)
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
checksum = f'{digest}  {asset}\n'
if mode == 'publish':
    checksum_name = asset + '.sha256'
    if any(a['name'] == checksum_name for a in assets):
        gh('release', 'download', tag, '--repo', repo, '--pattern', checksum_name, '--dir', str(folder), '--clobber')
        if (folder / checksum_name).read_text() != checksum:
            raise SystemExit('Existing checksum differs; never overwrite release assets')
    else:
        (folder / checksum_name).write_text(checksum)
        gh('release', 'upload', tag, str(folder / checksum_name), '--repo', repo)
    if release['draft']:
        gh('release', 'edit', tag, '--repo', repo, '--draft=false', '--latest=false')
elif mode == 'cask':
    if release['draft']:
        raise SystemExit('Tap requires published release')
    gh('release', 'download', tag, '--repo', repo, '--pattern', asset + '.sha256', '--dir', str(folder), '--clobber')
    if (folder / (asset + '.sha256')).read_text() != checksum:
        raise SystemExit('Published checksum mismatch')
    subprocess.run(['python3', 'scripts/release-cask.py', v, digest, repo, sys.argv[3]], check=True)
else:
    raise SystemExit('Unknown release mode')
