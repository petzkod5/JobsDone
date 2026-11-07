"""Exercise the real compiler gate in an isolated copy, without running the app."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('swiftc'), 'macOS Swift required')
class TypecheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='jobsdone-typecheck-')
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        shutil.copyfile(ROOT / 'Package.swift', cls.root / 'Package.swift')
        for directory in ('Sources', 'Tests'):
            shutil.copytree(ROOT / directory, cls.root / directory)
        (cls.root / 'scripts').mkdir()
        for source in (ROOT / 'scripts').glob('*.swift'):
            shutil.copyfile(source, cls.root / 'scripts' / source.name)
        for name in ('typecheck.sh', 'test.sh'):
            shutil.copy2(ROOT / 'scripts' / name, cls.root / 'scripts' / name)

    def check(self, path=None, addition=''):
        destination = self.root / path if path else None
        original = destination.read_text() if destination and destination.exists() else None
        try:
            if destination:
                destination.write_text((original or '') + '\n' + addition + '\n')
            return subprocess.run(['bash', str(self.root / 'scripts/typecheck.sh')],
                                  capture_output=True, text=True, timeout=180)
        finally:
            if destination:
                if original is None:
                    destination.unlink()
                else:
                    destination.write_text(original)

    def rejects(self, path, addition):
        result = self.check(path, addition)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('typecheckFixture', result.stdout + result.stderr)

    def test_valid_repository_passes(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_app_type_error_fails(self):
        self.rejects('Sources/TypecheckFixture.swift', 'let typecheckFixture: Int = "wrong"')

    def test_compiler_warning_fails(self):
        self.rejects('Tests/TypecheckFixture.swift', '#warning("typecheckFixture")')

    def test_shared_mutable_state_fails(self):
        self.rejects('Tests/TypecheckFixture.swift',
                     'enum TypecheckState { static var typecheckFixture = 0 }')

    def test_test_target_type_error_fails(self):
        self.rejects('Tests/TypecheckFixture.swift', 'let typecheckFixture: Int = "wrong"')

    def test_dev_only_type_error_fails(self):
        self.rejects('Sources/TypecheckFixture.swift',
                     '#if JOBSDONE_DEV\nlet typecheckFixture: Int = "wrong"\n#endif')

    def test_native_harness_type_error_fails(self):
        self.rejects('Tests/Native/main.swift', 'let typecheckFixture: Int = "wrong"')

    def test_utility_type_error_fails(self):
        self.rejects('scripts/typecheck-fixture.swift', 'let typecheckFixture: Int = "wrong"')


if __name__ == '__main__':
    unittest.main()
