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


if __name__ == "__main__":
    unittest.main()
