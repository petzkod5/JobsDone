"""Exercise the sound resource packaging boundary with isolated files."""
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "copy-sound-packs.sh"


class SoundPackPackagingTests(unittest.TestCase):
    def test_folders_and_unique_native_aliases(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for pack in ["peon", "second"]:
                source = root / "Resources" / "SoundPacks" / pack
                source.mkdir(parents=True)
                for event in ["opened", "merged", "committed", "issueOpened"]:
                    (source / f"{event}.wav").write_bytes(f"{pack}:{event}".encode())
            (root / "Resources" / "SoundPacks" / "README.md").write_text("Pack documentation")
            destination = root / "output"
            subprocess.run(["bash", str(SCRIPT), str(destination)], cwd=root, check=True)
            for pack in ["peon", "second"]:
                for event in ["opened", "merged", "committed", "issueOpened"]:
                    expected = f"{pack}:{event}".encode()
                    self.assertEqual((destination / "SoundPacks" / pack / f"{event}.wav").read_bytes(), expected)
                    self.assertEqual((destination / f"{pack}-{event}.wav").read_bytes(), expected)

    def test_missing_event_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "Resources" / "SoundPacks" / "broken").mkdir(parents=True)
            result = subprocess.run(["bash", str(SCRIPT), str(root / "output")], cwd=root, capture_output=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
