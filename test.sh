#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
build_dir="${BUILD_DIR:-$project_dir/.build/local}"
build_dir="${build_dir:A}"
mkdir -p "$build_dir/module-cache"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
swiftc -parse-as-library \
  "$project_dir/Sources/Soniclet/Localization.swift" \
  "$project_dir/Sources/Soniclet/Devices.swift" \
  "$project_dir/Tests/SonicletTests/DevicePreferencesTests.swift" \
  -o "$build_dir/DevicePreferencesTests"
"$build_dir/DevicePreferencesTests"
swiftc -parse-as-library \
  "$project_dir/Tests/SonicletTests/LocalizationChecks.swift" \
  -o "$build_dir/LocalizationChecks"
"$build_dir/LocalizationChecks" "$project_dir/Soniclet.app"
