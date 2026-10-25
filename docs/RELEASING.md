# Releasing Soniclet

## Current status

The public repository and app identity are fixed: `pal4de/soniclet`, bundle ID `io.github.pal4de.soniclet`. The first implementation is reviewed in PR #1; `main` has only an empty bootstrap commit until that PR is merged. Do not auto-merge it.

The app has original Icon Composer artwork and a GitHub Releases update notifier. Builds are **ad-hoc signed by default**. Developer ID signing and actual notarization remain unverified until a developer account and signing credentials are available. Do not publish a claim that a build is notarized based on compilation alone.

## What Apple signing requires

1. An [Apple Developer Program membership](https://developer.apple.com/programs/enroll/) (normally US$99 per year, or local pricing). Choose the individual or organization enrollment appropriate to the publisher. The account holder handles enrollment, payment, identity verification, and Apple agreements.
2. A **Developer ID Application** certificate and its private key in the signing Mac's keychain. A free Apple account, Apple Development certificate, ad-hoc signature, or Apple Distribution certificate is not a substitute for this direct-download distribution path. See [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates).
3. Hardened Runtime and a secure timestamp in the app signature. Soniclet needs no special Hardened Runtime exception entitlements.
4. Notarization authentication: either an Apple account with an app-specific password and team ID, or an appropriate App Store Connect API key. Create a local `notarytool` keychain profile interactively; do not paste passwords or private keys into chat, source, or release notes.
5. Submit the signed build, wait for Apple's **Accepted** status, staple the ticket, and verify Gatekeeper before distribution. This is separate from App Store review; Soniclet is distributed through GitHub Releases.

References: [Apple notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Build and validate

Xcode 27 is required for both the SwiftUI API and the Icon Composer asset compiler. Build Apple Silicon and Intel together:

```sh
ARCHS='arm64 x86_64' ./build.sh
./test.sh
./test-settings.sh
```

The last command needs a logged-in graphical macOS session. CI builds the GUI test without pretending to execute it headlessly. Complete the README's hardware/accessibility checklist as well; cross-compilation does not verify Intel hardware or HomePod connectivity.

For a Developer ID build, use an existing keychain signing identity:

```sh
CODE_SIGN_IDENTITY='Developer ID Application: YOUR PUBLISHER (TEAMID)' \
  ARCHS='arm64 x86_64' ./build.sh
```

`build.sh` enables Hardened Runtime and timestamping for that signature. It neither provisions a certificate nor accepts Apple agreements.

Create a keychain profile using Apple's interactive command, then notarize and package:

```sh
xcrun notarytool store-credentials SonicletNotary
./Tools/notarize.sh Soniclet.app SonicletNotary release/Soniclet-universal.zip
```

The helper refuses ad-hoc signatures before contacting Apple. It stages the app outside synced folders, submits it, checks the Accepted result, staples and verifies the ticket, checks Gatekeeper, and creates a ZIP from the stapled app. Retain the submission log when diagnosing a rejection. The successful Apple path cannot be tested without membership and credentials.

For CI signing later, use a protected GitHub environment and secrets for the certificate/private key and notary credentials, import into a temporary keychain, and remove it after the job. Do not store secrets in workflow inputs, print them, or run a signing job on untrusted pull-request code. The existing draft-release workflow intentionally produces ad-hoc builds until this is configured.

## GitHub Releases

1. Review the implementation PR and CI result before merging.
2. Set `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`. Commit and tag the reviewed version as `vMAJOR.MINOR.PATCH`; do not move a published tag.
3. The manual **Prepare draft release** workflow builds the tag, runs tests, verifies both CPU slices and the signature, and creates a **draft** with an ad-hoc ZIP and SHA-256 manifest. It does not publish automatically.
4. For the signed distribution path, replace the ad-hoc asset with the notarized ZIP, regenerate SHA-256, and clearly describe the signature status in the draft. Never label the current ad-hoc workflow's output as notarized.
5. Inspect extracted contents, version, architectures, signature, artwork, and ticket on a separate Mac. Check upgrade behavior and existing preferences, then publish the reviewed draft manually.

The update checker uses GitHub's latest stable release API. Only published, stable `vMAJOR.MINOR.PATCH` (or `MAJOR.MINOR.PATCH`) tags count. Drafts and prereleases do not trigger update notices. Until the first release is published, manual checks correctly report no newer release.
