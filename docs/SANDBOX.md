# App Sandbox compatibility

Local investigation: 2026-10-26, macOS 27.2 (26B118), SDK 27.0. No App Store approval or final distribution signing is implied.

## Build separation

`DISTRIBUTION_CHANNEL=app-store ./build.sh` compiles `MAC_APP_STORE`, signs with `Configuration/AppStore.entitlements`, and writes `.build/app-store/Soniclet.app`. Default direct builds still produce `Soniclet.app`. `APP_BUNDLE_ID` and `OUTPUT_APP` support isolated local trials; do not install a trial over the everyday app or enable its automatic routing during verification.

The store profile contains only `com.apple.security.app-sandbox`. Tests did not require audio-input, microphone, Bluetooth, network, or temporary-exception entitlements for the Core Audio metadata/default-control operations exercised. No audio recording or permission prompts were used. This does not prove every physical route change or hardware driver works.

GitHub update checking and cached GitHub update notices are compiled out of the store variant. Its update action opens the App Store; the direct version retains GitHub Releases notifications. An offline regression rejects any GitHub requests in store-mode checking.

## Observations

A separate application compared non-sandboxed, sandbox-only, network-client, Bluetooth, and combined Bluetooth/network profiles. Only strictly signed, containerized runs with denied access to an external test canary were accepted as sandbox evidence. One early network probe had an invalid signature and was excluded and rerun from a clean temporary directory. Raw device names, addresses and profiler JSON are not committed.

| Capability | Observed result | Limit |
| --- | --- | --- |
| Core Audio device discovery | Four input and four output entries visible in baseline and sandbox runs | Only currently attached hardware |
| Default input/output | Read succeeded; setting each current device back to itself returned success | Different-device switching was intentionally not performed |
| Volume | Control capability was visible; exact per-channel values could be written back unchanged | No audible level change, mute toggle or recording test |
| Default-change observation | Listener registration/removal succeeded | Callback delivery after physical reconnect is separate |
| Preferences | Isolated container preferences writable | Migration from the direct-download app not verified |
| Feedback sound and SF Symbols | Installed volume feedback resource readable; AirPods symbol available | Does not establish model identification or audible playback |
| System settings links | Sound URL handler and headphone extension path resolved | Navigation and per-device pane selection remain separate |
| Login items | SMAppService status readable | Register/unregister and login execution not exercised; no login entry created |
| GitHub networking | Denied without network-client; HTTP 404 reached with network-client | Store variant does not need this entitlement or GitHub checks |
| Bluetooth report | system_profiler ran with exit 0 but returned an empty 48-byte report in sandbox-only, network-only, Bluetooth-only and combined profiles | Baseline returned connected accessory and battery data |

The Bluetooth result means the existing report cannot preserve battery values, model IDs used for some exact AirPods/Beats symbols, or the address used by the dedicated headphone-settings link. The existing generic Core Audio symbol and Bluetooth Settings fallback still apply. No private selector, unrestricted helper, or temporary mach-lookup exception was added to escape this restriction.

The actual app's sandbox GUI smoke test passed with a container home and a denied read of its external source file, covering settings reopening, native menu tracking/dismissal, fixed status-item width and destination-preview restoration. Foreground activation assertions were explicitly skipped. This is separate from physical switching and login-item testing.

## Still required before submission

- Decide whether the Bluetooth feature difference is acceptable or identify a supported public alternative.
- Test actual input/output changes, volume/mute changes and physical connect/disconnect under a correctly signed store build, at an agreed time.
- Test login registration/unregistration and login execution with the intended signed bundle in its final location.
- Validate direct/store preference migration and avoid concurrent installations/login entries.
- Complete Apple Developer membership, store provisioning/signing, packaging, App Store Connect metadata and review.

References: [App Sandbox configuration](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox), [sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/).
