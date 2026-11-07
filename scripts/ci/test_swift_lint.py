"""Exercise the production lint runner and hook against disposable Git indexes."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[2]


class SwiftLintTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("scripts/lint.py", ".githooks/pre-commit", ".swiftlint.yml"):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SOURCE / name, target)
        binary = self.root / ".local/tools/swiftlint/swiftlint"
        binary.parent.mkdir(parents=True)
        binary.symlink_to(SOURCE / ".local/tools/swiftlint/swiftlint")
        self.git("init", "-q")
        (self.root / "Example.swift").write_text("let value = 1\n")
        self.git("add", "scripts", ".githooks", ".swiftlint.yml", "Example.swift")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True)

    def run_lint(self, staged=False):
        command = ["bash", ".githooks/pre-commit"] if staged else ["python3", "scripts/lint.py"]
        return subprocess.run(command, cwd=self.root, capture_output=True, text=True)

    def test_clean(self):
        self.assertEqual(self.run_lint().returncode, 0)
        self.assertEqual(self.run_lint(staged=True).returncode, 0)

    def test_warning_fails_and_worktree_cannot_hide_staged_error(self):
        path = self.root / "Example.swift"
        path.write_text("let value = 1;\n")
        self.git("add", "Example.swift")
        path.write_text("let value = 1\n")
        result = self.run_lint(staged=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("trailing_semicolon", result.stdout)
        self.assertEqual(self.run_lint().returncode, 0)
        self.assertEqual(path.read_text(), "let value = 1\n")

    def test_unstaged_error_does_not_block_clean_index(self):
        (self.root / "Example.swift").write_text("let value = 1;\n")
        self.assertEqual(self.run_lint(staged=True).returncode, 0)
        self.assertNotEqual(self.run_lint().returncode, 0)

    def test_inline_suppression_rejected_before_lint(self):
        (self.root / "Example.swift").write_text("// swift" + "lint:disable all\nlet value = 1;\n")
        result = self.run_lint()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("directives are forbidden", result.stderr)

    def test_nested_config_rejected(self):
        (self.root / "nested").mkdir()
        (self.root / "nested/.swiftlint.yml").write_text("disabled_rules: [trailing_semicolon]\n")
        self.assertIn("Nested SwiftLint", self.run_lint().stderr)

    def test_new_file_with_spaces_and_staged_deletion(self):
        path = self.root / "New File.swift"
        path.write_text("let other = 1;\n")
        self.git("add", path.name)
        self.assertNotEqual(self.run_lint(staged=True).returncode, 0)
        self.git("rm", "-f", path.name)
        self.assertEqual(self.run_lint(staged=True).returncode, 0)

    def test_missing_and_wrong_version_fail_closed(self):
        binary = self.root / ".local/tools/swiftlint/swiftlint"
        binary.unlink()
        self.assertIn("Missing SwiftLint", self.run_lint(staged=True).stderr)
        binary.write_text("#!/bin/sh\necho 0.0.0\n")
        binary.chmod(0o755)
        self.assertIn("Use SwiftLint 0.65.1", self.run_lint(staged=True).stderr)


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "scripts").mkdir()
        for name in ("setup-lint.sh", "setup-hooks.sh"):
            shutil.copy2(SOURCE / "scripts" / name, self.root / "scripts" / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"])
        self.fake("uname", "echo Darwin")

    def fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    def setup(self, name="setup-lint.sh"):
        return subprocess.run(["bash", "scripts/" + name], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def test_download_failure_does_not_install(self):
        self.fake("curl", "exit 22")
        self.assertNotEqual(self.setup().returncode, 0)
        self.assertFalse((self.root / ".local/tools/swiftlint/swiftlint").exists())

    def test_bad_checksum_stops_before_extraction(self):
        self.fake("curl", 'while [[ "$1" != -o ]]; do shift; done; echo bad > "$2"')
        self.fake("unzip", 'echo unexpected-unzip >&2; exit 1')
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("unexpected-unzip", result.stderr)
        self.assertFalse((self.root / ".local/tools/swiftlint/swiftlint").exists())

    def test_existing_hook_path_is_preserved(self):
        subprocess.run(["git", "init", "-q"], cwd=self.root, check=True)
        subprocess.run(["git", "config", "core.hooksPath", "custom-hooks"], cwd=self.root, check=True)
        self.assertNotEqual(self.setup("setup-hooks.sh").returncode, 0)
        value = subprocess.check_output(["git", "config", "core.hooksPath"], cwd=self.root, text=True)
        self.assertEqual(value.strip(), "custom-hooks")


if __name__ == "__main__":
    unittest.main()
