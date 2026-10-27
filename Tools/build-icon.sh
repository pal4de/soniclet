#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
build_dir="${1:A}"
resources="${2:A}"
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
asset_compiler="$developer_dir/usr/bin/actool"
if [[ ! -x "$asset_compiler" ]]; then
  asset_compiler="/Applications/Xcode.app/Contents/Developer/usr/bin/actool"
fi
[[ -x "$asset_compiler" ]] || { print -u2 "Xcode 27's asset compiler is required to build the Icon Composer artwork."; exit 1; }
mkdir -p "$build_dir" "$resources"
"$asset_compiler" "$project_dir/Assets/Soniclet.icon" \
  --compile "$resources" --app-icon Soniclet --platform macosx \
  --minimum-deployment-target 14.0 \
  --output-partial-info-plist "$build_dir/icon-info.plist" \
  --output-format human-readable-text
