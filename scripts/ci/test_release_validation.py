import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'release-validate.sh'


@unittest.skipUnless(sys.platform == 'darwin', 'Archive validator uses macOS tools')
class ReleaseValidationTests(unittest.TestCase):
    def validate(self, authority=True, producer_exit=0, stapler_exit=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = root / 'bin'
            commands.mkdir()
            fixtures = {
                'codesign': '''#!/usr/bin/env python3
import os, signal, sys
if '-d' in sys.argv:
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    if os.environ['TEST_AUTHORITY'] == 'true':
        sys.stderr.write('Authority=Developer ID Application: Test\\n')
        sys.stderr.flush()
    for _ in range(128):
        os.write(2, b'diagnostic output ' * 4096 + b'\\n')
    sys.exit(int(os.environ['TEST_PRODUCER_EXIT']))
''',
                'lipo': '#!/bin/sh\nprintf "arm64 x86_64\\n"\n',
                'xcrun': '#!/bin/sh\ncase "$1" in vtool) printf "minos 13.0\\n";; stapler) exit "$TEST_STAPLER_EXIT";; *) exit 1;; esac\n',
            }
            for name, content in fixtures.items():
                command = commands / name
                command.write_text(content)
                command.chmod(0o755)
            archive = root / 'app.zip'
            with zipfile.ZipFile(archive, 'w') as package:
                package.writestr('Job’s Done.app/Contents/Info.plist', plistlib.dumps({
                    'CFBundleShortVersionString': '1.3.0',
                    'CFBundleVersion': '1.3.0',
                    'LSMinimumSystemVersion': '13.0',
                }))
                package.writestr('Job’s Done.app/Contents/MacOS/JobsDone', b'fixture')
            env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ['PATH'], MACOS_SIGNING_ENABLED='true', TEST_AUTHORITY=str(authority).lower(), TEST_PRODUCER_EXIT=str(producer_exit), TEST_STAPLER_EXIT=str(stapler_exit))
            return subprocess.run(['bash', str(SCRIPT), str(archive), '1.3.0'], env=env, capture_output=True, text=True)

    def test_matching_authority_drains_verbose_output_without_sigpipe(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_nonmatching_authority_is_rejected(self):
        self.assertNotEqual(self.validate(authority=False).returncode, 0)

    def test_failed_codesign_still_fails_with_matching_authority(self):
        self.assertEqual(self.validate(producer_exit=7).returncode, 7)

    def test_failed_ticket_validation_still_rejects_archive(self):
        self.assertEqual(self.validate(stapler_exit=1).returncode, 1)


if __name__ == '__main__':
    unittest.main()
