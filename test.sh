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

swiftc -parse-as-library \
  "$project_dir/Sources/Soniclet/ReleaseFeed.swift" \
  "$project_dir/Sources/Soniclet/UpdateChecker.swift" \
  "$project_dir/Sources/Soniclet/Localization.swift" \
  "$project_dir/Tests/SonicletTests/ReleaseFeedTests.swift" \
  -o "$build_dir/ReleaseFeedTests"
"$build_dir/ReleaseFeedTests"

swiftc -parse-as-library \
  "$project_dir/Sources/Soniclet/StatusMark.swift" \
  "$project_dir/Sources/Soniclet/DeviceMenuIcon.swift" \
  "$project_dir/Tests/SonicletTests/StatusMarkTests.swift" \
  -o "$build_dir/StatusMarkTests"
"$build_dir/StatusMarkTests" "$project_dir/Soniclet.app"

swiftc -parse-as-library \
  "$project_dir/Sources/Soniclet/AudioAccessories.swift" \
  "$project_dir/Tests/SonicletTests/AudioAccessoryTests.swift" \
  -o "$build_dir/AudioAccessoryTests"
"$build_dir/AudioAccessoryTests"

swiftc -parse-as-library \
  "$project_dir/Sources/Soniclet/Localization.swift" \
  "$project_dir/Sources/Soniclet/Devices.swift" \
  "$project_dir/Sources/Soniclet/AutomaticRouting.swift" \
  "$project_dir/Tests/SonicletTests/AutomaticRoutingTests.swift" \
  -o "$build_dir/AutomaticRoutingTests"
"$build_dir/AutomaticRoutingTests"

swiftc -parse-as-library \
  "$project_dir/Sources/Soniclet/Localization.swift" \
  "$project_dir/Sources/Soniclet/Devices.swift" \
  "$project_dir/Sources/Soniclet/DeviceSelectionProgress.swift" \
  "$project_dir/Tests/SonicletTests/DeviceSelectionProgressTests.swift" \
  -o "$build_dir/DeviceSelectionProgressTests"
"$build_dir/DeviceSelectionProgressTests"
