"""Exercise the shared macOS runner gate on fixtures and the tracked workflows."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/check-runners.py'


def job(runner):
    return f'name: Fixture\non: push\njobs:\n  fixture:\n    runs-on: {runner}\n    steps:\n      - run: echo fixture\n'


class RunnerCheckTests(unittest.TestCase):
    def check(self, workflows):
        with tempfile.TemporaryDirectory() as temporary:
            for name, content in workflows.items():
                (Path(temporary) / name).write_text(content)
            return subprocess.run([sys.executable, str(SCRIPT), temporary], capture_output=True, text=True)

    def test_tracked_workflows_share_one_pinned_macos_runner(self):
        """Detect release and PR-check jobs drifting onto different Swift toolchains."""
        result = subprocess.run([sys.executable, str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_one_pinned_macos_runner_passes(self):
        """Detect false failures for Linux jobs, comments, quotes, or .yaml files."""
        result = self.check({'build.yml': job('macos-26'), 'release.yaml': job("'macos-26' # release"),
                             'commits.yml': job('ubuntu-latest')})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_release_runner_differing_from_checks_fails(self):
        """Detect the v1.6.0 failure: release on macos-15 while checks ran on macOS 26."""
        result = self.check({'build.yml': job('macos-26'), 'release.yml': job('macos-15')})
        self.assertEqual(result.returncode, 1)
        self.assertIn('macos-15 at release.yml:5; macos-26 at build.yml:5', result.stderr)

    def test_floating_macos_runner_fails(self):
        """Detect a label that moves to a new Xcode without a reviewed change."""
        result = self.check({'build.yml': job('macos-latest')})
        self.assertEqual(result.returncode, 1)
        self.assertIn('build.yml:5: pin a macOS version instead of macos-latest', result.stderr)

    def test_unparsed_runner_forms_fail(self):
        """Detect matrix expressions or YAML lists that could hide a different macOS label."""
        result = self.check({'matrix.yml': job('${{ matrix.os }}'), 'list.yml': job('\n      - macos-15')})
        self.assertEqual(result.returncode, 1)
        self.assertIn('matrix.yml:5: runs-on must be one literal runner label', result.stderr)
        self.assertIn("list.yml:5: runs-on must be one literal runner label, not 'a block'", result.stderr)

    def test_alternate_key_spellings_are_checked(self):
        """Detect valid YAML key spellings that a plain `runs-on:` match would skip."""
        spaced = ('name: Fixture\non: push\njobs:\n'
                  '  build:\n    runs-on : macos-26\n    steps:\n      - run: echo fixture\n'
                  "  release:\n    'runs-on': macos-latest\n    steps:\n      - run: echo fixture\n")
        result = self.check({'spaced.yml': spaced})
        self.assertEqual(result.returncode, 1)
        self.assertIn('spaced.yml:9: pin a macOS version instead of macos-latest', result.stderr)
        self.assertIn('macos-26 at spaced.yml:5; macos-latest at spaced.yml:9', result.stderr)

    def test_mixed_case_macos_label_is_checked(self):
        """Detect labels that GitHub matches case-insensitively, such as macOS-latest."""
        result = self.check({'build.yml': job('macos-26'), 'release.yml': job('macOS-latest')})
        self.assertEqual(result.returncode, 1)
        self.assertIn('release.yml:5: pin a macOS version instead of macos-latest', result.stderr)

    def test_flow_mapping_fails(self):
        """Detect runner labels hidden in flow-style job mappings."""
        flow = 'name: Fixture\non: push\njobs:\n  fixture: {runs-on: macos-15, steps: [{run: echo fixture}]}\n'
        result = self.check({'build.yml': job('macos-26'), 'flow.yml': flow})
        self.assertEqual(result.returncode, 1)
        self.assertIn('flow.yml:4: write runs-on as a block key with one literal label', result.stderr)


if __name__ == '__main__':
    unittest.main()
