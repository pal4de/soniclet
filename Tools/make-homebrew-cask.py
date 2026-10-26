#!/usr/bin/env python3
"""Create a reviewable cask from the exact direct-download release archive."""
import argparse
import hashlib
import plistlib
import re
from pathlib import Path
from zipfile import ZipFile


def render(archive: Path) -> str:
    with ZipFile(archive) as package:
        info = plistlib.loads(package.read('Soniclet.app/Contents/Info.plist'))
    version = info.get('CFBundleShortVersionString', '')
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise ValueError('Casks require a stable MAJOR.MINOR.PATCH version')
    if info.get('CFBundleIdentifier') != 'io.github.pal4de.soniclet':
        raise ValueError('Archive has the wrong application identity')
    if info.get('SonicletDistributionChannel') != 'direct':
        raise ValueError('Homebrew must distribute the direct-download build')
    if info.get('LSMinimumSystemVersion') != '14.0':
        raise ValueError('Review the cask macOS dependency when changing the deployment target')
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    return f'''cask "soniclet" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/pal4de/soniclet/releases/download/v#{{version}}/Soniclet-universal.zip"
  name "Soniclet"
  desc "Switch audio devices from the menu bar"
  homepage "https://github.com/pal4de/soniclet"

  depends_on macos: :sonoma

  app "Soniclet.app"

  uninstall quit: "io.github.pal4de.soniclet"

  zap trash: "~/Library/Preferences/io.github.pal4de.soniclet.plist"
end
'''


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path, help='Final Soniclet-universal.zip; regenerate after notarization/repackaging')
    parser.add_argument('output', type=Path, help='Staged soniclet.rb; review before committing to the tap')
    args = parser.parse_args()
    content = render(args.archive)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding='utf-8')
    print(f'Prepared {args.output}; publish the matching release before enabling the cask')


if __name__ == '__main__':
    main()
