#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
build_dir="${BUILD_DIR:-$project_dir/.build/local}"
build_dir="${build_dir:A}"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/SonicletSettingsTest.XXXXXX")"
app_dir="$stage_dir/Soniclet Settings Test.app"
channel="${DISTRIBUTION_CHANNEL:-direct}"
default_app="$project_dir/Soniclet.app"
[[ "$channel" == app-store ]] && default_app="$project_dir/.build/app-store/Soniclet.app"
source_app="${APP_PATH:-$default_app}"
swift_flags=()
signing_flags=()
if [[ "$channel" == app-store ]]; then
  swift_flags+=(-D MAC_APP_STORE)
  signing_flags+=(--entitlements "$project_dir/Configuration/AppStore.entitlements")
fi
ditto --norsrc --noextattr "$source_app" "$app_dir"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
swiftc -O -parse-as-library -D SETTINGS_SMOKE_TEST -target "$(uname -m)-apple-macosx14.0" \
  $swift_flags "$project_dir"/Sources/Soniclet/*.swift \
  "$project_dir/Tests/SonicletTests/SettingsSmokeTest.swift" \
  -o "$app_dir/Contents/MacOS/Soniclet"
test_id="io.github.pal4de.soniclet.settings-test"
[[ "$channel" == app-store ]] && test_id="$test_id.sandbox"
plutil -replace CFBundleIdentifier -string "$test_id" "$app_dir/Contents/Info.plist"
codesign --force --sign - $signing_flags "$app_dir"
codesign --verify --deep --strict "$app_dir"
if [[ "${1:-}" == "--build-only" ]]; then
  print -r -- "$app_dir" > "$build_dir/settings-test-app-path.txt"
  print "Built native test app: $app_dir"
else
  "$app_dir/Contents/MacOS/Soniclet" "$@"
fi
