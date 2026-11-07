#!/usr/bin/env python3
"""Sign an app with a temporary Developer ID keychain and restore user keychains."""
import base64
import os
from functools import partial
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile

INTERMEDIATE = Path(__file__).resolve().parent / 'certificates' / 'DeveloperIDG2CA.cer'


def run(label, *args, sensitive=()):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        detail = result.stderr.strip()
        for secret in sorted(set(sensitive), key=len, reverse=True):
            if secret:
                detail = detail.replace(secret, '***')
        suffix = f': {detail}' if detail else ''
        raise RuntimeError(f'{label} failed (exit {result.returncode}){suffix}')
    return result.stdout


def sign(app):
    certificate = os.environ['MACOS_CERTIFICATE_BASE64']
    certificate_password = os.environ['MACOS_CERTIFICATE_PASSWORD']
    identity = os.environ['MACOS_SIGNING_IDENTITY']
    if not identity.strip():
        raise RuntimeError('Configured signing identity must not be empty')
    execute = partial(run, sensitive=(certificate_password, certificate))
    original = shlex.split(execute('Read keychain search list', 'security', 'list-keychains', '-d', 'user'))
    with tempfile.TemporaryDirectory(prefix='jobsdone-sign-') as temporary:
        directory = Path(temporary)
        keychain = str(directory / 'release.keychain-db')
        password = secrets.token_hex(24)
        execute = partial(run, sensitive=(certificate_password, certificate, password))
        created = False
        try:
            (directory / 'certificate.p12').write_bytes(base64.b64decode(''.join(certificate.split()), validate=True))
            (directory / 'certificate.p12').chmod(0o600)
            (directory / 'intermediate.cer').write_bytes(INTERMEDIATE.read_bytes())
            execute('Create signing keychain', 'security', 'create-keychain', '-p', password, keychain)
            created = True
            execute('Configure signing keychain', 'security', 'set-keychain-settings', '-lut', '21600', keychain)
            execute('Unlock signing keychain', 'security', 'unlock-keychain', '-p', password, keychain)
            execute('Register signing keychain', 'security', 'list-keychains', '-d', 'user', '-s', keychain, *original)
            execute('Import Developer ID intermediate', 'security', 'import', str(directory / 'intermediate.cer'), '-k', keychain)
            execute('Import signing identity', 'security', 'import', str(directory / 'certificate.p12'), '-f', 'pkcs12', '-k', keychain, '-P', certificate_password, '-T', '/usr/bin/codesign')
            execute('Authorize signing key access', 'security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain)
            identities = execute('Validate signing identity', 'security', 'find-identity', '-v', '-p', 'codesigning', keychain)
            if identity not in identities:
                raise RuntimeError('Configured signing identity is not valid in the temporary keychain')
            execute('Sign app', 'codesign', '--force', '--options', 'runtime', '--timestamp', '--keychain', keychain, '--sign', identity, str(app))
            execute('Verify signed app', 'codesign', '--verify', '--deep', '--strict', str(app))
        finally:
            primary_error = sys.exc_info()[1]
            cleanup_errors = []
            if created:
                for label, args in (
                    ('Restore keychain search list', ('security', 'list-keychains', '-d', 'user', '-s', *original)),
                    ('Delete signing keychain', ('security', 'delete-keychain', keychain)),
                ):
                    try:
                        execute(label, *args)
                    except (RuntimeError, OSError) as error:
                        cleanup_errors.append(error)
            if cleanup_errors:
                if primary_error is not None:
                    for error in cleanup_errors:
                        print(str(error), file=sys.stderr)
                else:
                    raise RuntimeError('; '.join(str(error) for error in cleanup_errors))


if __name__ == '__main__':
    try:
        sign(Path(sys.argv[1]).resolve())
    except (RuntimeError, OSError, KeyError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
