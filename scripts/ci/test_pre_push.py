"""Exercise Git's hook input and committed snapshots with a compiler-boundary stub."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
ZERO = '0' * 40


class PrePushTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='jobsdone hook ')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = dict(os.environ)
        for name in ('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE'):
            self.env.pop(name, None)
        for name in ('.githooks/pre-push', 'scripts/pre-push.py'):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
        checker = self.root / 'scripts/typecheck.sh'
        checker.write_text('''#!/bin/bash
set -euo pipefail
printf 'CHECKED: %s\\n' "$(cat Marker)"
touch build-created
[[ "$(cat Marker)" != bad ]]
''')
        checker.chmod(0o755)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Hook Test')
        self.git('config', 'user.email', 'hook@example.invalid')
        self.valid = self.commit('good')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, env=self.env,
                                       text=True).strip()

    def commit(self, value):
        (self.root / 'Marker').write_text(value)
        self.git('add', '.')
        self.git('commit', '-qm', 'test: update fixture')
        return self.git('rev-parse', 'HEAD')

    def run_hook(self, *oids, raw=None):
        text = raw if raw is not None else ''.join(
            f'refs/heads/fixture{index} {oid} refs/heads/fixture{index} {ZERO}\n'
            for index, oid in enumerate(oids))
        return subprocess.run(['.githooks/pre-push', 'origin', 'unused'], cwd=self.root,
                              env=self.env, input=text, capture_output=True, text=True)

    def test_committed_error_cannot_be_hidden_by_worktree(self):
        invalid = self.commit('bad')
        (self.root / 'Marker').write_text('good')
        before = self.git('status', '--porcelain')
        result = self.run_hook(invalid)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('CHECKED: bad', result.stdout)
        self.assertEqual(self.git('status', '--porcelain'), before)
        self.assertEqual((self.root / 'Marker').read_text(), 'good')
        self.assertFalse((self.root / 'build-created').exists())

    def test_valid_commit_ignores_uncommitted_error(self):
        (self.root / 'Marker').write_text('bad')
        result = self.run_hook(self.valid)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('CHECKED: good', result.stdout)
        self.assertEqual((self.root / 'Marker').read_text(), 'bad')

    def test_each_pushed_tip_is_checked(self):
        invalid = self.commit('bad')
        self.git('checkout', '-q', self.valid)
        result = self.run_hook(self.valid, invalid)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('CHECKED: good', result.stdout)
        self.assertIn('CHECKED: bad', result.stdout)

    def test_annotated_tags_are_peeled_and_duplicates_checked_once(self):
        self.git('tag', '-am', 'fixture', 'fixture')
        result = self.run_hook(self.valid, self.git('rev-parse', 'fixture'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.count('CHECKED: good'), 1)

    def test_delete_unchanged_and_empty_pushes_skip_checker(self):
        for raw in ('', f'(delete) {ZERO} refs/heads/old {self.valid}\n',
                    f'refs/heads/same {self.valid} refs/heads/same {self.valid}\n'):
            with self.subTest(raw=raw):
                result = self.run_hook(raw=raw)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertNotIn('CHECKED:', result.stdout)

    def test_missing_checker_blocks_push(self):
        self.git('rm', '-q', 'scripts/typecheck.sh')
        self.git('commit', '-qm', 'test: remove fixture checker')
        result = self.run_hook(self.git('rev-parse', 'HEAD'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Pre-push type checking failed', result.stderr)

    def test_malformed_hook_input_blocks_push(self):
        result = self.run_hook(raw='invalid\n')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Expected four fields', result.stderr)


if __name__ == '__main__':
    unittest.main()
