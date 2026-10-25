# Soniclet

A small, native macOS menu-bar utility for choosing audio input and output devices. [日本語](README.ja.md)

[GitHub](https://github.com/pal4de/soniclet)

- Switch the Mac's default audio input and output.
- Hide unused devices from this app, independently for input and output.
- Adjust output volume; the buttons at either end move by one normal volume-key step (1/16).
- Right-click the menu-bar icon for the current devices, output mute, settings, and quit.
- Launch at login using macOS ServiceManagement.
- Follow macOS language preferences, with 34 bundled translations.

Device visibility only changes this app's list. It does not remove devices from macOS or change another app's explicit device selection. This app uses public Core Audio APIs; it does not record audio, install a driver, or process audio streams.

## Requirements and build

macOS 14 or later. Building the current native settings implementation requires the macOS 27 SDK and Swift 6.4 (Xcode 27 or the corresponding Command Line Tools). No third-party packages are required.

```sh
./build.sh
./test.sh
open 'Soniclet.app'
```

The scripts work from a standalone checkout. Set `BUILD_DIR` to override `.build/local`. The generated app is ad-hoc signed for local use, **not Developer ID signed or notarized**. macOS may block downloaded builds. Release signing and notarization remain a publication prerequisite to resolve; do not disable Gatekeeper globally.

`Package.swift` describes the executable and localization resources; the scripts also assemble the actual menu-bar app bundle and are the supported build path.

## Use

Click the speaker in the menu bar. Choose a device, or open **Soniclet Settings…** and uncheck devices you do not want to see. All newly discovered devices are visible by default. Disconnected ordinary devices retain their visibility setting for reconnection.

Output volume and mute depend on hardware support. For fixed-volume outputs, adjust volume on the device. Applications that explicitly select their own device may ignore the system default.

### AirPlay

Connect an AirPlay device through **System Sound Settings…** first. This app lists devices exposed by Core Audio; it cannot discover or connect all unconnected AirPlay destinations such as HomePod. An active AirPlay endpoint may appear with a generic name. Disconnected AirPlay session endpoints are not retained as permanent devices.

## Validation

`./test.sh` checks device preference persistence, reconnects, malformed-data recovery, AirPlay cleanup, and localization bundle lookups, placeholders, and locale fallback.

```sh
./test-settings.sh
```

The integration smoke test needs a logged-in graphical macOS session. It checks accessory-app settings presentation, reopening, fixed icon width, native context menu structure, and popover placement. Headless CI runs build and non-UI tests; it does not prove physical-device switching, HomePod connectivity, or visual behavior on every supported macOS version.

Manual checks before a release: built-in and USB input/output switching; unplug/replug; sleep/wake; fixed-volume HDMI; keyboard and VoiceOver access; light/dark appearance; long translations and RTL layout; settings reopening; login-item registration; upgrade with existing preferences.

## Architecture and contributions

AppKit owns the status item, native contextual menu, and popover. SwiftUI provides the content and settings scene, with a small AppKit window fallback on macOS 14–25. Core Audio owns routing and volume state; ServiceManagement owns login-item state. User preferences are stored locally in UserDefaults.

See [AGENTS.md](AGENTS.md) for implementation principles and validation. Translation corrections and focused bug reports are welcome. Include macOS version, app version, device type, and reproduction steps; redact personal device names. Translations have automated consistency checks but have not all been reviewed by native speakers.

## Upgrading development builds

Soniclet imports device visibility preferences from the earlier local Sound Switch build once, only when no Soniclet preferences exist. Login-item registration remains under user control. Quit the old app before launching Soniclet.

## Privacy

No telemetry or audio capture. Device names and visibility preferences remain on the Mac. A planned GitHub Releases update check will contact GitHub over HTTPS; it will not send device names or audio settings. No automatic installer is included.

## Release status

Original app artwork, update checking, and the signing/notarization path are being prepared. No public release is implied by a successful local build. See [docs/RELEASING.md](docs/RELEASING.md).

## License

[MIT](LICENSE).
