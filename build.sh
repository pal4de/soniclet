#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
output_app_dir="$project_dir/Soniclet.app"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/Soniclet.XXXXXX")"
app_dir="$staging_dir/Soniclet.app"
build_dir="${BUILD_DIR:-$project_dir/.build/local}"
build_dir="${build_dir:A}"
mkdir -p "$build_dir/module-cache" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
# ARCHS="arm64 x86_64" builds a universal executable; default is the host CPU.
architectures=(${=ARCHS:-$(uname -m)})
binaries=()
for architecture in $architectures; do
  [[ "$architecture" == arm64 || "$architecture" == x86_64 ]] || { print -u2 "Unsupported architecture: $architecture"; exit 1; }
  binary="$build_dir/Soniclet-$architecture"
  swiftc -O -parse-as-library -target "$architecture-apple-macosx14.0" \
    "$project_dir"/Sources/Soniclet/*.swift -o "$binary"
  binaries+=("$binary")
done
lipo -create $binaries -output "$app_dir/Contents/MacOS/Soniclet"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
ditto --norsrc --noextattr "$project_dir/Sources/Soniclet/Resources" "$app_dir/Contents/Resources"
cp "$project_dir/Assets/Soniclet.icon/Assets/Routing.svg" "$app_dir/Contents/Resources/StatusMark.svg"
"$project_dir/Tools/build-icon.sh" "$build_dir" "$app_dir/Contents/Resources"
xattr -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
signing_identity="${CODE_SIGN_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
  codesign --force --sign - "$app_dir"
else
  codesign --force --options runtime --timestamp --sign "$signing_identity" "$app_dir"
fi
codesign --verify --deep --strict "$app_dir"
ditto --norsrc --noextattr "$app_dir" "$output_app_dir"
# Finder may attach display metadata to app bundles under synced folders.
xattr -d com.apple.FinderInfo "$output_app_dir" 2>/dev/null || true
print "Built: $output_app_dir"
