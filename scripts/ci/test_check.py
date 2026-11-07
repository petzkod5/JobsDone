"""Exercise the check command against isolated, tracked repository fixtures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

CHECK = Path(__file__).resolve().parents[1] / 'check.sh'
RUNNERS = Path(__file__).resolve().parents[1] / 'check-runners.py'


@unittest.skipUnless(shutil.which('actionlint') and shutil.which('shellcheck'), 'Pinned lint tools required')
class AutomationCheckTests(unittest.TestCase):
    def check(self, shell='#!/bin/bash\necho "fixture"\n', workflow_extra='', runner='ubuntu-latest'):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'scripts').mkdir()
            shutil.copyfile(CHECK, root / 'scripts/check.sh')
            shutil.copyfile(RUNNERS, root / 'scripts/check-runners.py')
            (root / 'scripts/fixture.sh').write_text(shell)
            workflows = root / '.github/workflows'
            workflows.mkdir(parents=True)
            (workflows / 'fixture.yml').write_text('''name: Fixture
on: push
jobs:
  check:
    runs-on: {runner}
    steps:
      - run: echo fixture
'''.format(runner=runner) + workflow_extra)
            env = dict(os.environ)
            # Keep parent repository discovery overrides out of the fixture.
            for key in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE'):
                env.pop(key, None)
            subprocess.run(['git', 'init', '-q', str(root)], check=True, env=env)
            subprocess.run(['git', '-C', str(root), 'add', '.'], check=True, env=env)
            return subprocess.run(['bash', str(root / 'scripts/check.sh')], env=env, capture_output=True, text=True)

    def test_valid_tracked_files_pass(self):
        """Detect broken tool invocation or repository discovery."""
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_shell_warning_fails(self):
        """Detect omitted shell files or ignored ShellCheck warning failures."""
        result = self.check(shell='#!/bin/bash\necho "$undefined_fixture_variable"\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SC2154', result.stdout + result.stderr)

    def test_invalid_workflow_fails(self):
        """Detect omitted workflows or ignored actionlint failures."""
        result = self.check(workflow_extra='    invalid_fixture_key: true\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('invalid_fixture_key', result.stdout + result.stderr)

    def test_floating_macos_runner_fails(self):
        """Detect check.sh skipping the shared macOS runner gate."""
        result = self.check(runner='macos-latest')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('pin a macOS version instead of macos-latest', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
