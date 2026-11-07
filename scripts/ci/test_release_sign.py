import base64
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release_sign', Path(__file__).resolve().parents[1] / 'release-sign.py')
release_sign = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_sign)


class ReleaseSigningTests(unittest.TestCase):
    def exercise(self, failure=None, valid_identity=True):
        identity = 'Developer ID Application: Test (TESTTEAM)'
        calls = []
        def run(label, *args):
            calls.append((label, args))
            if label == failure:
                raise RuntimeError(label + ' failed')
            if label == 'Read keychain search list':
                return '"/Users/test/Library/Keychains/login.keychain-db"\n"/Library/Keychains/System.keychain"'
            if label == 'Validate signing identity':
                return identity if valid_identity else '0 valid identities found'
            return ''
        env = {'MACOS_CERTIFICATE_BASE64': base64.b64encode(b'test fixture').decode(), 'MACOS_CERTIFICATE_PASSWORD': 'test-password', 'MACOS_SIGNING_IDENTITY': identity}
        with patch.dict(os.environ, env), patch.object(release_sign, 'run', side_effect=run), patch.object(release_sign, 'urlopen', return_value=io.BytesIO(b'intermediate fixture')):
            try:
                release_sign.sign(Path('/tmp/test.app'))
            except RuntimeError:
                if failure is None and valid_identity:
                    raise
            else:
                self.assertIsNone(failure)
                self.assertTrue(valid_identity)
        return calls

    def test_imports_chain_and_registers_keychain_before_signing(self):
        calls = self.exercise()
        labels = [label for label, args in calls]
        self.assertLess(labels.index('Register signing keychain'), labels.index('Sign app'))
        self.assertLess(labels.index('Import Developer ID intermediate'), labels.index('Validate signing identity'))
        self.assertLess(labels.index('Import signing identity'), labels.index('Sign app'))
        self.assertEqual(labels[-2:], ['Restore keychain search list', 'Delete signing keychain'])
        restored = calls[-2][1]
        self.assertEqual(restored[-2:], ('/Users/test/Library/Keychains/login.keychain-db', '/Library/Keychains/System.keychain'))

    def test_failure_restores_search_list_and_deletes_keychain(self):
        for phase in ['Register signing keychain', 'Import signing identity', 'Authorize signing key access', 'Sign app', 'Verify signed app']:
            with self.subTest(phase=phase):
                calls = self.exercise(phase)
                self.assertEqual([label for label, args in calls][-2:], ['Restore keychain search list', 'Delete signing keychain'])

    def test_missing_valid_identity_stops_before_signing(self):
        calls = self.exercise(valid_identity=False)
        self.assertNotIn('Sign app', [label for label, args in calls])
        self.assertEqual([label for label, args in calls][-2:], ['Restore keychain search list', 'Delete signing keychain'])

    def test_failed_command_does_not_expose_secret_arguments(self):
        with patch.object(subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'secret-password')):
            with self.assertRaisesRegex(RuntimeError, 'Import identity failed') as error:
                release_sign.run('Import identity', 'security', 'import', '-P', 'secret-password')
            self.assertNotIn('secret-password', str(error.exception))


if __name__ == '__main__':
    unittest.main()
