import json
import os
from pathlib import Path
import runpy
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "release.py"


class ReleaseIdentityTests(unittest.TestCase):
    def test_resolve_uses_draft_aware_lookup_and_numeric_release_endpoint(self):
        repo = "petzkod5/JobsDone"
        sha = "a" * 40
        calls = []
        def fake_output(arguments, **kwargs):
            args = tuple(arguments)
            calls.append(args)
            responses = {
                ("gh", "release", "view", "v1.2.0", "--repo", repo, "--json", "databaseId", "--jq", ".databaseId"): "123\n",
                ("gh", "api", f"repos/{repo}/releases/123"): json.dumps({"tag_name": "v1.2.0", "draft": True, "prerelease": False}),
                ("git", "fetch", "--no-tags", "origin", "refs/tags/v1.2.0", "refs/heads/main"): "",
                ("gh", "api", f"repos/{repo}/git/ref/tags/v1.2.0", "--jq", ".object.sha"): sha,
                ("git", "rev-parse", sha + "^{commit}"): sha,
                ("gh", "api", f"repos/{repo}/git/ref/heads/main", "--jq", ".object.sha"): sha,
                ("git", "merge-base", "--is-ancestor", sha, sha): "",
                ("git", "show", sha + ":version.txt"): "1.2.0\n",
                ("git", "show", sha + ":.release-please-manifest.json"): '{".":"1.2.0"}',
            }
            if args not in responses:
                raise AssertionError(f"Unexpected command: {args}")
            return responses[args]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            with patch.dict(os.environ, GITHUB_REPOSITORY=repo, GITHUB_OUTPUT=str(output)), patch.object(sys, "argv", [str(SCRIPT), "resolve", "v1.2.0"]), patch("subprocess.check_output", side_effect=fake_output):
                with self.assertRaises(SystemExit) as exit:
                    runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertIsNone(exit.exception.code)
            self.assertEqual(output.read_text(), f"tag=v1.2.0\nsha={sha}\n")
            self.assertFalse(any("releases/tags/" in arg for call in calls for arg in call))


    def test_publish_runs_current_tools_in_the_tagged_source_directory(self):
        import hashlib
        repo, sha = "petzkod5/JobsDone", "a" * 40
        archive_name = "JobsDone-1.2.0-universal.zip"
        calls = []
        def fake_output(arguments, **kwargs):
            args = tuple(arguments)
            calls.append(args)
            if args[:3] == ("gh", "release", "view"):
                return "123"
            if args == ("gh", "api", f"repos/{repo}/releases/123"):
                return json.dumps({"tag_name": "v1.2.0", "draft": True, "prerelease": False, "assets": []})
            if args[:2] == ("git", "fetch") or args[:2] == ("git", "merge-base"):
                return ""
            if args[:2] == ("git", "rev-parse") or args[:2] == ("gh", "api"):
                return sha
            if args[:2] == ("git", "show"):
                return "1.2.0" if args[2].endswith(":version.txt") else '{".":"1.2.0"}'
            if args[:3] == ("gh", "release", "download"):
                (Path("dist/downloaded") / archive_name).write_bytes(b"archive fixture")
                return ""
            if args[:3] in [("gh", "release", "upload"), ("gh", "release", "edit")]:
                return ""
            raise AssertionError(args)
        def fake_run(arguments, **kwargs):
            args = tuple(arguments)
            calls.append(args)
            if args == ("bash", str(SCRIPT.parent / "release-package.sh"), str(Path.cwd())):
                Path("dist/release").mkdir(parents=True)
                (Path("dist/release") / archive_name).write_bytes(b"archive fixture")
            elif args != ("bash", str(SCRIPT.parent / "release-validate.sh"), "dist/downloaded/" + archive_name, "1.2.0"):
                raise AssertionError(args)
        previous = Path.cwd()
        try:
            with tempfile.TemporaryDirectory() as directory:
                os.chdir(directory)
                with patch.dict(os.environ, GITHUB_REPOSITORY=repo, MACOS_SIGNING_ENABLED="false"), patch.object(sys, "argv", [str(SCRIPT), "publish", "v1.2.0"]), patch("subprocess.check_output", side_effect=fake_output), patch("subprocess.run", side_effect=fake_run):
                    runpy.run_path(str(SCRIPT), run_name="__main__")
                self.assertIn(("bash", str(SCRIPT.parent / "release-package.sh"), str(Path(directory).resolve())), calls)
                checksum = (Path("dist/downloaded") / (archive_name + ".sha256")).read_text()
                self.assertTrue(checksum.startswith(hashlib.sha256(b"archive fixture").hexdigest()))
        finally:
            os.chdir(previous)


if __name__ == "__main__":
    unittest.main()
