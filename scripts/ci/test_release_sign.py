import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_sign', Path(__file__).resolve().parents[1] / 'release-sign.py')
release_sign = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_sign)

IDENTITY = 'Developer ID Application: Fixture (TESTTEAM)'
ORIGINAL = ['/Users/fixture/Library/Keychains/login keychain-db', '/Library/Keychains/System.keychain']
APP = Path('/tmp/requested app with spaces.app')


class ReleaseSigningTests(unittest.TestCase):
    def exercise(self, failure=None, valid_identity=True):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            commands = root / 'bin'
            commands.mkdir()
            for name in ('security', 'codesign'):
                executable = commands / name
                # Use the active interpreter even when Python is absent from PATH.
                executable.write_text('#!' + os.sys.executable + '\n' + Path(__file__).with_name('signing_command.py').read_text())
                executable.chmod(0o755)
            log = root / 'commands.jsonl'
            env = {
                'PATH': str(commands), 'SIGN_TEST_LOG': str(log),
                'SIGN_TEST_FAILURE': failure or '', 'SIGN_TEST_INVALID': '' if valid_identity else '1',
                'MACOS_CERTIFICATE_BASE64': base64.b64encode(b'certificate fixture').decode(),
                'MACOS_CERTIFICATE_PASSWORD': 'fixture-password', 'MACOS_SIGNING_IDENTITY': IDENTITY,
            }
            labels = {
                'create-keychain': 'Create signing keychain', 'set-keychain-settings': 'Configure signing keychain',
                'unlock-keychain': 'Unlock signing keychain', 'register': 'Register signing keychain',
                'intermediate': 'Import Developer ID intermediate', 'identity': 'Import signing identity',
                'set-key-partition-list': 'Authorize signing key access', 'find-identity': 'Validate signing identity',
                'sign': 'Sign app', 'verify': 'Verify signed app', 'restore': 'Restore keychain search list',
                'delete-keychain': 'Delete signing keychain', 'read': 'Read keychain search list',
            }
            with patch.dict(os.environ, env), patch.object(release_sign, 'urlopen', return_value=io.BytesIO(b'intermediate fixture')) as download:
                if failure:
                    expected = labels[failure] + ' failed (exit 37)'
                elif not valid_identity:
                    expected = 'Configured signing identity is not valid in the temporary keychain'
                else:
                    expected = None
                if expected:
                    with self.assertRaisesRegex(RuntimeError, '^' + re.escape(expected) + '$') as error:
                        release_sign.sign(APP)
                    self.assertNotIn('fixture-password', str(error.exception))
                    self.assertNotIn('private fixture diagnostic', str(error.exception))
                else:
                    release_sign.sign(APP)
                if failure != 'read':
                    download.assert_called_once_with(release_sign.INTERMEDIATE_URL, timeout=30)
            records = [json.loads(line) for line in log.read_text().splitlines()]
        return records

    def test_signing_command_contract(self):
        """Detect wrong executables, arguments, credentials, order, or signing target."""
        records = self.exercise()
        calls = [record['command'] for record in records]
        keychain = calls[1][-1]
        directory = Path(keychain).parent
        password = calls[1][3]
        self.assertTrue(password)
        self.assertEqual(Path(keychain).name, 'release.keychain-db')
        self.assertEqual(calls, [
            ['security', 'list-keychains', '-d', 'user'],
            ['security', 'create-keychain', '-p', password, keychain],
            ['security', 'set-keychain-settings', '-lut', '21600', keychain],
            ['security', 'unlock-keychain', '-p', password, keychain],
            ['security', 'list-keychains', '-d', 'user', '-s', keychain, *ORIGINAL],
            ['security', 'import', str(directory / 'intermediate.cer'), '-k', keychain],
            ['security', 'import', str(directory / 'certificate.p12'), '-f', 'pkcs12', '-k', keychain, '-P', 'fixture-password', '-T', '/usr/bin/codesign'],
            ['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, keychain],
            ['security', 'find-identity', '-v', '-p', 'codesigning', keychain],
            ['codesign', '--force', '--options', 'runtime', '--timestamp', '--keychain', keychain, '--sign', IDENTITY, str(APP)],
            ['codesign', '--verify', '--deep', '--strict', str(APP)],
            ['security', 'list-keychains', '-d', 'user', '-s', *ORIGINAL],
            ['security', 'delete-keychain', keychain],
        ])
        self.assertEqual(base64.b64decode(records[5]['data']), b'intermediate fixture')
        self.assertEqual(base64.b64decode(records[6]['data']), b'certificate fixture')
        self.assertEqual(records[6]['mode'], 0o600)
        self.assertFalse(directory.exists(), 'Temporary credential files must be removed')

    def test_failure_restores_search_list_and_deletes_keychain(self):
        """Detect swallowed command failures or omitted cleanup after keychain creation."""
        for phase in ('set-keychain-settings', 'unlock-keychain', 'register', 'intermediate', 'identity',
                      'set-key-partition-list', 'find-identity', 'sign', 'verify', 'restore', 'delete-keychain'):
            with self.subTest(phase=phase):
                calls = [record['command'] for record in self.exercise(phase)]
                keychain = calls[1][-1]
                self.assertEqual(calls[-2:], [
                    ['security', 'list-keychains', '-d', 'user', '-s', *ORIGINAL],
                    ['security', 'delete-keychain', keychain],
                ])
                self.assertFalse(Path(keychain).parent.exists())

    def test_failure_before_creation_does_not_delete_uncreated_keychain(self):
        """Detect cleanup of a keychain this invocation did not create."""
        for phase in ('read', 'create-keychain'):
            with self.subTest(phase=phase):
                calls = [record['command'] for record in self.exercise(phase)]
                self.assertEqual(len(calls), 1 if phase == 'read' else 2)

    def test_missing_valid_identity_stops_before_signing(self):
        """Detect signing despite an identity absent from the selected keychain."""
        calls = [record['command'] for record in self.exercise(valid_identity=False)]
        self.assertFalse(any(call[0] == 'codesign' for call in calls))
        self.assertEqual(calls[-2], ['security', 'list-keychains', '-d', 'user', '-s', *ORIGINAL])
        self.assertEqual(calls[-1], ['security', 'delete-keychain', calls[1][-1]])

    def test_failed_command_does_not_expose_secret_arguments(self):
        """Detect inclusion of subprocess secrets in public failure messages."""
        with patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'secret-password')):
            with self.assertRaisesRegex(RuntimeError, '^Import identity failed \\(exit 1\\)$') as error:
                release_sign.run('Import identity', 'security', 'import', '-P', 'secret-password')
            self.assertNotIn('secret-password', str(error.exception))


if __name__ == '__main__':
    unittest.main()
