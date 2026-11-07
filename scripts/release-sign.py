#!/usr/bin/env python3
"""Sign an app with a temporary Developer ID keychain and restore user keychains."""
import base64
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile
from urllib.request import urlopen

INTERMEDIATE_URL = 'https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer'


def run(label, *args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise RuntimeError(f'{label} failed (exit {result.returncode})')
    return result.stdout


def sign(app):
    certificate = os.environ['MACOS_CERTIFICATE_BASE64']
    certificate_password = os.environ['MACOS_CERTIFICATE_PASSWORD']
    identity = os.environ['MACOS_SIGNING_IDENTITY']
    original = shlex.split(run('Read keychain search list', 'security', 'list-keychains', '-d', 'user'))
    with tempfile.TemporaryDirectory(prefix='jobsdone-sign-') as temporary:
        directory = Path(temporary)
        keychain = str(directory / 'release.keychain-db')
        password = secrets.token_hex(24)
        created = False
        try:
            (directory / 'certificate.p12').write_bytes(base64.b64decode(certificate, validate=True))
            (directory / 'certificate.p12').chmod(0o600)
            with urlopen(INTERMEDIATE_URL, timeout=30) as response:
                (directory / 'intermediate.cer').write_bytes(response.read())
            run('Create signing keychain', 'security', 'create-keychain', '-p', password, keychain)
            created = True
            run('Configure signing keychain', 'security', 'set-keychain-settings', '-lut', '21600', keychain)
            run('Unlock signing keychain', 'security', 'unlock-keychain', '-p', password, keychain)
            run('Register signing keychain', 'security', 'list-keychains', '-d', 'user', '-s', keychain, *original)
            run('Import Developer ID intermediate', 'security', 'import', str(directory / 'intermediate.cer'), '-k', keychain)
            run('Import signing identity', 'security', 'import', str(directory / 'certificate.p12'), '-f', 'pkcs12', '-k', keychain, '-P', certificate_password, '-T', '/usr/bin/codesign')
            run('Authorize signing key access', 'security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain)
            identities = run('Validate signing identity', 'security', 'find-identity', '-v', '-p', 'codesigning', keychain)
            if identity not in identities:
                raise RuntimeError('Configured signing identity is not valid in the temporary keychain')
            run('Sign app', 'codesign', '--force', '--options', 'runtime', '--timestamp', '--keychain', keychain, '--sign', identity, str(app))
            run('Verify signed app', 'codesign', '--verify', '--deep', '--strict', str(app))
        finally:
            if created:
                try:
                    run('Restore keychain search list', 'security', 'list-keychains', '-d', 'user', '-s', *original)
                finally:
                    run('Delete signing keychain', 'security', 'delete-keychain', keychain)


if __name__ == '__main__':
    try:
        sign(Path(sys.argv[1]).resolve())
    except (RuntimeError, OSError, KeyError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
