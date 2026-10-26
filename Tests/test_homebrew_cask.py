import hashlib
import importlib.util
import plistlib
import tempfile
import unittest
import sys
from pathlib import Path
from zipfile import ZipFile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('cask', Path(__file__).parents[1] / 'Tools/make-homebrew-cask.py')
cask = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cask)


class ReleaseCaskTests(unittest.TestCase):
    def archive(self, directory, **overrides):
        info = dict(CFBundleShortVersionString='1.2.3', CFBundleIdentifier='io.github.pal4de.soniclet',
                    SonicletDistributionChannel='direct', LSMinimumSystemVersion='14.0')
        info.update(overrides)
        archive = Path(directory) / 'Soniclet-universal.zip'
        with ZipFile(archive, 'w') as package:
            package.writestr('Soniclet.app/Contents/Info.plist', plistlib.dumps(info))
        return archive

    def test_exact_archive_hash_and_stable_url(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = self.archive(directory)
            rendered = cask.render(archive)
            self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(), rendered)
            self.assertIn('version "1.2.3"', rendered)
            self.assertIn('/v#{version}/Soniclet-universal.zip', rendered)
            self.assertNotIn('auto_updates', rendered)  # Notifications do not install updates.
            self.assertNotIn(':no_check', rendered)

    def test_rejects_wrong_channel_identity_and_target(self):
        for override in [dict(SonicletDistributionChannel='app-store'),
                         dict(CFBundleIdentifier='io.github.pal4de.soniclet.trial'),
                         dict(LSMinimumSystemVersion='15.0')]:
            with self.subTest(override=override), tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):
                    cask.render(self.archive(directory, **override))

    def test_rejects_prerelease_and_ruby_injection(self):
        for version in ['1.2.3-beta.1', 'latest', '1.2.3"; system("false")', '01.2.3']:
            with self.subTest(version=version), tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(ValueError):
                    cask.render(self.archive(directory, CFBundleShortVersionString=version))


if __name__ == '__main__':
    unittest.main()
