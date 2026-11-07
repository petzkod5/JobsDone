import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("validator", Path(__file__).with_name("check-conventional-commits.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ConventionalCommitsTests(unittest.TestCase):
    def test_subjects_and_breaking_changes(self):
        for message in ["feat: add alerts", "fix(monitor): deduplicate", "feat!: change setup", "refactor(api)!: remove an endpoint", "chore(main): release 1.3.0", "fix: change setup\n\nBREAKING CHANGE: new config required"]:
            with self.subTest(message=message):
                self.assertEqual(validator.errors(message), [])
        for message in ["", "WIP", "feat: ", "feat:no space", " feat: leading space", "fixup! fix: alert", "Merge branch 'main'", "fix: alert\nbody without separator", "FEAT: uppercase", "fix(): empty scope"]:
            with self.subTest(message=message):
                self.assertTrue(validator.errors(message))

    def test_complete_history_and_title(self):
        with tempfile.TemporaryDirectory() as directory:
            original = os.getcwd()
            try:
                os.chdir(directory)
                env = dict(os.environ, GIT_AUTHOR_NAME="Test", GIT_AUTHOR_EMAIL="test@example.com", GIT_COMMITTER_NAME="Test", GIT_COMMITTER_EMAIL="test@example.com")
                def git(*args, data=None):
                    return subprocess.check_output(["git", *args], input=data, text=True, env=env).rstrip("\n")
                git("init", "-q")
                tree = git("mktree", data="")
                base = git("commit-tree", tree, "-m", "Old project history")
                head = base
                invalid = None
                for index in range(270):
                    message = "Missing conventional type" if index == 4 else f"fix: change {index}"
                    head = git("commit-tree", tree, "-p", head, "-m", message)
                    if index == 4:
                        invalid = head
                pr = {"base": {"sha": base}, "head": {"sha": head}, "title": "feat: add releases"}
                commits, failures = validator.check(pr, head)
                self.assertEqual(len(commits), 270)
                self.assertEqual(len(failures), 1)
                self.assertIn(invalid[:12], failures[0])
                pr["base"]["sha"] = invalid
                clean_commits, clean_failures = validator.check(pr, head)
                self.assertEqual(len(clean_commits), 265)
                self.assertEqual(clean_failures, [])
                pr["base"]["sha"] = base
                pr["title"] = "Add releases"
                self.assertEqual(len(validator.check(pr, head)[1]), 2)
                with self.assertRaisesRegex(ValueError, "head changed"):
                    validator.check(pr, base)
                pr["base"]["sha"] = "--all"
                with self.assertRaisesRegex(ValueError, "invalid commit IDs"):
                    validator.check(pr, head)
            finally:
                os.chdir(original)


if __name__ == "__main__":
    unittest.main()
