# Soniclet artwork

`Soniclet.icon` is the editable Icon Composer document. Its embedded `Assets/Routing.svg` is the original vector mark: two independent opposing audio routes around a standalone waveform, with a square silhouette and a subtle S-like arrangement. The artwork is covered by the repository's MIT license.

Edit the material and appearances with Apple's Icon Composer. `Tools/build-icon.sh` calls Apple's `actool` to compile both the adaptive asset catalog and the `.icns` fallback for macOS 14–25. The menu-bar speaker remains a native SF Symbol.

`StatusMark.svg` is the menu-bar-specific variant, with thinner arrows and heavier, separated volume bars. The app draws it at the same width with a shorter, vertically centered silhouette. Its three named bars receive runtime opacity changes; this does not change the full-size app icon.

`Preview.png` is a documentation preview; the app uses the compiled Icon Composer document, not this PNG. Regenerate the preview using Icon Composer's export feature, or its bundled `ictool`:

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  Assets/Soniclet.icon --export-image --output-file Assets/Preview.png \
  --platform macOS --rendition Default --width 256 --height 256 --scale 1
```

Do not commit generated `Assets.car`, `.icns`, or app bundles. Icon Composer may require accepting Apple's first-run license in the app; automated builds must never accept it on a user's behalf.
