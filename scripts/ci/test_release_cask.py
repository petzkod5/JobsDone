from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "release-cask.py"


class ReleaseCaskTests(unittest.TestCase):
    def test_retry_checksum_and_downgrade_protection(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "Casks/jobsdone.rb"
            def generate(version, digest):
                return subprocess.run(["python3", str(SCRIPT), version, digest, "petzkod5/JobsDone", str(target)], capture_output=True, text=True)
            self.assertEqual(generate("1.3.0", "a" * 64).returncode, 0)
            original = target.read_bytes()
            self.assertEqual(generate("1.3.0", "a" * 64).returncode, 0)
            self.assertEqual(target.read_bytes(), original)
            self.assertNotEqual(generate("1.3.0", "b" * 64).returncode, 0)
            self.assertEqual(target.read_bytes(), original)
            self.assertEqual(generate("1.2.9", "b" * 64).returncode, 0)
            self.assertEqual(target.read_bytes(), original)
            self.assertNotEqual(generate("1.4.0; echo unsafe", "b" * 64).returncode, 0)
            self.assertEqual(target.read_bytes(), original)
            self.assertEqual(generate("1.4.0", "b" * 64).returncode, 0)
            self.assertIn(b'version "1.4.0"', target.read_bytes())
            self.assertEqual(subprocess.run(["ruby", "-c", str(target)], capture_output=True).returncode, 0)


if __name__ == "__main__":
    unittest.main()
