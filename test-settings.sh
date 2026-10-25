#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
build_dir="${BUILD_DIR:-$project_dir/.build/local}"
build_dir="${build_dir:A}"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/SoundSwitchSettingsTest.XXXXXX")"
app_dir="$stage_dir/Sound Switch Settings Test.app"
ditto --norsrc --noextattr "$project_dir/Sound Switch.app" "$app_dir"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache-v4"
swiftc -O -parse-as-library -D SETTINGS_SMOKE_TEST -target "$(uname -m)-apple-macosx14.0" \
  "$project_dir"/Sources/SoundSwitch/*.swift \
  "$project_dir/Tests/SoundSwitchTests/SettingsSmokeTest.swift" \
  -o "$app_dir/Contents/MacOS/SoundSwitch"
plutil -replace CFBundleIdentifier -string local.sound-switch.settings-test "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
if [[ "${1:-}" == "--build-only" ]]; then
  print -r -- "$app_dir" > "$build_dir/settings-test-app-path.txt"
  print "Built native test app: $app_dir"
else
  "$app_dir/Contents/MacOS/SoundSwitch"
fi
