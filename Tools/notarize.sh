#!/bin/zsh
# Use a profile created interactively with `xcrun notarytool store-credentials`.
set -euo pipefail
[[ $# -ge 2 && $# -le 3 ]] || { print -u2 "Usage: $0 /path/to/Soniclet.app keychain-profile [output.zip]"; exit 2; }
source_app="${1:A}"
profile="$2"
output_zip="${3:-${source_app:h}/Soniclet-notarized.zip}"
output_zip="${output_zip:A}"
# Stage outside synced folders; Finder display metadata can invalidate verification.
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/SonicletNotarization.XXXXXX")"
app_dir="$stage_dir/Soniclet.app"
ditto --norsrc --noextattr "$source_app" "$app_dir"
codesign --verify --deep --strict "$app_dir"
signing_info="$(codesign --display --verbose=4 "$app_dir" 2>&1)"
[[ "$signing_info" == *"Authority=Developer ID Application:"* && "$signing_info" == *"(runtime)"* ]] || {
  print -u2 "A Developer ID Application signature with Hardened Runtime is required. Ad-hoc builds cannot be notarized."
  exit 1
}
ditto -c -k --keepParent "$app_dir" "$stage_dir/submit.zip"
xcrun notarytool submit "$stage_dir/submit.zip" --keychain-profile "$profile" --wait --output-format json > "$stage_dir/result.json"
result_status="$(plutil -extract status raw -o - "$stage_dir/result.json")"
if [[ "$result_status" != "Accepted" ]]; then
  print -u2 "Notarization was not accepted. Inspect $stage_dir/result.json and the Apple notary log."
  exit 1
fi
xcrun stapler staple "$app_dir"
xcrun stapler validate "$app_dir"
spctl --assess --type execute --verbose=2 "$app_dir"
mkdir -p "${output_zip:h}"
# Preserve the stapled ticket when packaging the accepted app.
ditto -c -k --keepParent "$app_dir" "$output_zip"
print "Notarization and Gatekeeper checks passed: $output_zip"
