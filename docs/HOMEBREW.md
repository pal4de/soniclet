# Homebrew Cask distribution

Soniclet is a GUI app, so distribute it as a **Cask**, not a source-built command-line Formula. A **Tap** is the Git repository containing cask definitions; it is not an alternative to Cask. The initial destination is `pal4de/homebrew-tap` (`pal4de/tap` in Homebrew), separate from the community-maintained `homebrew/cask` repository.

The cask installs the same universal direct-download ZIP as GitHub Releases. It does not rebuild the app, use the App Store variant, disable quarantine, add a privileged helper, or maintain a separate audio implementation. Its version and SHA-256 identify one exact archive. The app only notifies about updates, so the cask must not set `auto_updates true`.

## After the first release and tap cask are published

```sh
brew install --cask pal4de/tap/soniclet
brew upgrade --cask pal4de/tap/soniclet
brew uninstall --cask pal4de/tap/soniclet
```

These are intended installation instructions, not a claim that a downloadable release exists yet. The tap starts with an empty bootstrap main and a draft implementation PR, like the application repository. Do not merge its initial cask while its asset URL is unavailable or its checksum still describes a development ZIP.

## Maintainer workflow

1. Build, sign, notarize and verify the final direct-download universal ZIP following [RELEASING.md](RELEASING.md). The expected asset name is `Soniclet-universal.zip`, attached to the matching stable tag `vMAJOR.MINOR.PATCH`.
2. Generate the definition from that exact final archive:

   ```sh
   python3 Tools/make-homebrew-cask.py release/Soniclet-universal.zip release/soniclet.rb
   ruby -c release/soniclet.rb
   ```

   The generator reads the bundled plist, rejects Store/trial identities, unstable versions and unexpected deployment targets, and calculates SHA-256. Re-run it whenever the ZIP changes, including after stapling/repackaging. The draft-release workflow also produces a staged definition, but its default ad-hoc artifact is not the final signed distribution.
3. Publish the reviewed matching GitHub Release. Copy `soniclet.rb` to `Casks/soniclet.rb` in `pal4de/homebrew-tap` and review it through a PR. No repository token or automatic cross-repository write is needed.
4. Run `brew style --cask Casks/soniclet.rb` and, once the release URL is live, `brew audit --cask --online --strict soniclet` from the tapped repository. Compare the downloaded archive's SHA-256, extracted version, both CPU slices, Developer ID signature and notarization with the release record. Test installation/upgrade separately on a clean account/Mac; do not overwrite a working copy just to validate packaging.
5. Merge the tap PR after these checks. Homebrew updates the app through `brew upgrade`; Soniclet's own release notifier remains available.

Normal uninstall removes the app, preserving preferences. Explicit `--zap` also removes the direct-download preferences. The cask deliberately does not remove the App Store container.

A later submission to `homebrew/cask` is separate and subject to its acceptance criteria; an independent tap does not imply official catalog acceptance.

References: [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [creating and maintaining a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap), [acceptable casks](https://docs.brew.sh/Acceptable-Casks).
