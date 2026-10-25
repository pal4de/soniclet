# Publication preparation

## Repository and first pull request

The owner is `pal4de`; the repository name remains undecided. Create `main` with an empty bootstrap commit, then put the complete application, documentation, tests, and workflows in a feature branch and the first PR. The empty commit exists only to give GitHub a comparison base. Do not auto-merge the PR.

The public payload is source, tests, build metadata/scripts, and documentation. Local apps, ZIPs, screenshots with personal device names, experiments, caches, and account data stay out of Git.

## Name directions

The name should retain a Japanese sound while allowing an international audience to understand the purpose. Candidates are working ideas, not cleared trademarks:

- **OtoPick** — short; choosing an audio device is the primary action.
- **OtoSelect** — explicit selection utility; slightly longer.
- **OtoPort** — evokes input/output endpoints; less explicit about switching.
- **Oto Switch** — direct; two words and a longer menu/settings name.

Possible English description: “A native audio switcher for your Mac.” Keep the brand unchanged across translations and translate descriptive labels.

## Original app icon

Use an original shape, rather than treating a system SF Symbol as the app's logo. The menu-bar icon remains the native template speaker symbol.

A suitable direction is two small opposing audio paths around a central selection point, readable at small sizes. Avoid tiny wave details and embedded lettering. Prepare editable vector foreground layers, test monochrome and small sizes, then assemble them with Apple's Icon Composer into a `.icon` document. Keep an `.icns` fallback for the macOS 14 minimum. The source artwork and generation instructions belong in the repository.

Apple's current workflow: https://developer.apple.com/icon-composer/ and https://developer.apple.com/documentation/Xcode/creating-your-app-icon-using-icon-composer

The local Xcode installation includes Icon Composer. Icon source and compiled artwork are not yet prepared. Do not fabricate a `.icon` bundle format or describe a static PNG as an adaptive icon.

## Update notification

Prefer a small GitHub Releases notifier using Foundation URLSession. No dependency or installer is necessary for the stated minimum.

- Configure the finalized owner/repository in build metadata, not a guessed URL.
- Check the latest stable release on launch at most once per 24 hours, with a bounded request timeout. Provide a manual check in the contextual menu.
- Compare numeric versions correctly (for example, 0.10.0 is newer than 0.9.0). Ignore drafts and prereleases in the stable channel.
- Show a menu item linking to the newer release. No notification permission, modal prompt at launch, automatic download, or code execution is needed.
- Validate HTTPS and the exact expected GitHub repository before opening a release URL.
- Treat no releases, offline operation, and rate limiting quietly during automatic checks; give an actionable result for a manual check.
- Disclose the GitHub request in the privacy note. Send no audio/device details.
- Test version comparison, missing/malformed fields, wrong release URLs, timeout/rate-limit handling, and the first release case with fixtures.

Implementation waits for final repository identity. The current app does not yet make update-check network requests.

## Other small publication essentials

- Stable bundle ID, minimum OS version, supported architectures, and preference migration from development builds.
- Explicit signing/notarization status and a reproducible release version/tag.
- Sanitized screenshots or a short demo, with useful alt text.
- A concise known-limitations section, especially AirPlay and fixed-volume devices.
- Hardware/accessibility checks beyond headless CI; native-speaker translation review as contributions arrive.
- Verify branch protection/required CI after the first checks exist. Avoid a large maintenance framework for a small utility.
