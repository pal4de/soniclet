# Release checklist

1. Finalize the public name, reverse-DNS bundle identifier, repository URL, and original app artwork before the first public release. Keep identifiers stable thereafter. Document migration from development builds.
2. Run build, preference/localization tests, and the graphical settings smoke test. Complete README's hardware and accessibility checks.
3. Set one version/build number for the app and tag. Create a reviewed release commit; do not edit a published tag or reuse a version.
4. Use the release workflow to build and create a **draft** GitHub Release. Inspect the ZIP, version, executable architecture, signature, resource bundle, and SHA-256 manifest.
5. Decide distribution trust: the initial workflow produces ad-hoc signed builds. For normal end-user distribution, add Developer ID signing and Apple notarization, then verify the notarization ticket. Store credentials only in GitHub environment secrets. Never describe ad-hoc artifacts as notarized.
6. Publish the reviewed draft manually. Verify downloading and launching on a separate Mac, and upgrading without losing preferences.

The initial implementation belongs in a pull request. `main` starts with an empty bootstrap commit so that GitHub has a comparison base. Do not push the implementation directly to `main`.

## Pending decisions

- App/repository name and stable bundle ID.
- Original icon and Icon Composer source, plus an older-macOS fallback.
- GitHub Releases update notifier: HTTPS only, bounded launch-time checks, manual check, release-link validation; no installer or downloaded-code execution.
- Developer ID and notarization availability.
- Confirm Intel behavior on hardware; cross-compilation alone is insufficient.
