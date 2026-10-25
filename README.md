# Soniclet

<img src="Assets/Preview.png" width="128" height="128" alt="Soniclet icon">

A small, native macOS menu-bar utility for choosing audio input and output devices. [日本語](README.ja.md)

[GitHub](https://github.com/pal4de/soniclet)

- Switch the Mac's default audio input and output.
- Hide unused devices from this app, independently for input and output.
- Adjust output volume; the buttons at either end move by one normal volume-key step (1/16).
- Right-click the menu-bar icon for the current devices, output mute, settings, and quit.
- Choose the standard speaker or Soniclet’s monochrome mark from the icon picker in Settings. The initial choice is the system icon; both picker previews use volume level two. Waveform bars brighten from left to right with volume; mute dims all three without a slash.
- Launch at login using macOS ServiceManagement.
- Follow macOS language preferences, with 34 bundled translations.
- See new stable GitHub Releases in the menu, with manual update checking.
- Use a headphone symbol for headphone outputs; show reported Bluetooth battery levels and a native settings link when available.

Device visibility only changes this app's list. It does not remove devices from macOS or change another app's explicit device selection. This app uses public Core Audio APIs; it does not record audio, install a driver, or process audio streams.

## Requirements and build

macOS 14 or later. Building requires Xcode 27: the macOS 27 SDK / Swift 6.4 and Apple’s Icon Composer asset compiler. No third-party packages are required.

```sh
./build.sh
./test.sh
open 'Soniclet.app'
```

The scripts work from a standalone checkout. Set `BUILD_DIR` to override `.build/local`. The generated app is ad-hoc signed for local use, **not Developer ID signed or notarized**. macOS may block downloaded builds. Developer ID signing and notarization require an Apple Developer Program membership and signing credentials; do not disable Gatekeeper globally.

`Package.swift` describes the executable and localization resources; the scripts also assemble the actual menu-bar app bundle and are the supported build path.

## Use

Click the speaker in the menu bar. Choose a device, or open **Soniclet Settings…** and uncheck devices you do not want to see. All newly discovered devices are visible by default. Disconnected ordinary devices retain their visibility setting for reconnection.

Output volume and mute depend on hardware support. For fixed-volume outputs, adjust volume on the device. Applications that explicitly select their own device may ignore the system default.

### AirPlay

Connect an AirPlay device through **System Sound Settings…** first. This app lists devices exposed by Core Audio; it cannot discover or connect all unconnected AirPlay destinations such as HomePod. An active AirPlay endpoint may appear with a generic name. Disconnected AirPlay session endpoints are not retained as permanent devices.

### Headphones and battery information

In system-icon mode, headphone outputs use the native headphone symbol. Soniclet-icon mode keeps the chosen app mark.

Bluetooth accessory metadata comes from macOS’s documented `system_profiler SPBluetoothDataType -json` utility, read off the main thread with a five-second report timeout. A refresh is requested on audio-device changes or menu opening, at most once per minute for an unchanged connection. Reports stay in memory and are never logged or sent to GitHub. Only connected entries are used. Hardware addresses take precedence over names; ambiguous names are not matched.

A battery value appears only when macOS reports one. For earbuds, the lower known left/right value is displayed; a charging-case value is never substituted. Some devices, including WH-1000XM3 in current testing, show a percentage in Apple's menu but do not expose it through this standard report. They remain blank here; no private battery selectors are used.

Connected Apple headphones get a link to the OS headphone settings panel when that panel is present; other Bluetooth audio devices get a Bluetooth Settings link. Noise control, spatial audio, and Conversation Awareness stay in Apple's settings instead of being reimplemented through private APIs.

## Validation

`./test.sh` checks device preference persistence, reconnects, malformed-data recovery, AirPlay cleanup, and localization bundle lookups, placeholders, and locale fallback.

```sh
./test-settings.sh
```

The integration smoke test needs a logged-in graphical macOS session. It checks accessory-app settings presentation, reopening, fixed icon width, native context menu structure, and native menu placement/tracking. Headless CI runs build and non-UI tests; it does not prove physical-device switching, HomePod connectivity, or visual behavior on every supported macOS version.

Manual checks before a release: built-in and USB input/output switching; unplug/replug; sleep/wake; fixed-volume HDMI; keyboard and VoiceOver access; light/dark appearance; long translations and RTL layout; settings reopening; login-item registration; upgrade with existing preferences.

## Architecture and contributions

AppKit owns the square status item and its permanently attached NSMenu, including placement, tracking, outside-click dismissal, and Escape. The menu delegate chooses the device controls or the right-click commands at opening time. The device menu embeds SwiftUI through NSMenuItem.view; it has no NSPopover arrow or popover animation. SwiftUI provides the controls and settings scene, with a small AppKit window fallback on macOS 14–25. Core Audio owns routing and volume state; ServiceManagement owns login-item state. User preferences are stored locally in UserDefaults.

See [AGENTS.md](AGENTS.md) for implementation principles and validation. Translation corrections and focused bug reports are welcome. Include macOS version, app version, device type, and reproduction steps; redact personal device names. Translations have automated consistency checks but have not all been reviewed by native speakers.

## Upgrading development builds

Soniclet imports device visibility preferences from the earlier local Sound Switch build once, only when no Soniclet preferences exist. Login-item registration remains under user control. Quit the old app before launching Soniclet.

## Privacy

No telemetry or audio capture. Device names and visibility preferences remain on the Mac. Automatic update checks contact GitHub over HTTPS on launch and when opening a menu, at most once per 24 hours. Manual checks are also available. Requests contain the app version, not device names or audio settings. A validated available-release notice survives restarts; drafts and prereleases are ignored. Automatic failures stay quiet; manual checks show a result. The app opens the release page only on request and never downloads or installs an update.

## Release status

Original Icon Composer artwork and GitHub Releases update notification are implemented. Developer ID signing is supported, with a notarization helper; the authenticated Apple path has not yet been exercised. No public release is implied by a successful local build. See [docs/RELEASING.md](docs/RELEASING.md).

## License

[MIT](LICENSE).
