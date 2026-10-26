# App Sandbox compatibility

Local investigation: 2026-10-26, macOS 27.2 (26B118), SDK 27.0. No App Store approval or final distribution signing is implied.

## Build separation

`DISTRIBUTION_CHANNEL=app-store ./build.sh` compiles `MAC_APP_STORE`, signs with `Configuration/AppStore.entitlements`, and writes `.build/app-store/Soniclet.app`. Default direct builds still produce `Soniclet.app`. `APP_BUNDLE_ID` and `OUTPUT_APP` support isolated local trials; do not install a trial over the everyday app or enable its automatic routing during verification.

The store profile contains `com.apple.security.app-sandbox` and `com.apple.security.device.bluetooth`. The latter is needed for public cached accessory metadata, with a localized Bluetooth usage description. Core Audio metadata/default-control tests did not need microphone, audio-input, network or temporary-exception entitlements. No audio was recorded. This does not prove every physical route change or hardware driver works.

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

### Public Bluetooth alternative

A second, permission-approved probe used public `IOBluetoothDevice.pairedDevices()`, `isConnected()`, `getServiceRecord(for:)` and SDP attribute accessors inside an enforced Sandbox with the Bluetooth entitlement. It read the existing system cache only: no scan, SDP query, connection or pairing. With AirPods Pro 2 connected, cached PnP metadata reported Apple vendor ID `0x004c` and product ID `0x2024`. The actual application backend also returned one audio accessory, one model-specific symbol and one normalized address inside Sandbox; its SDP vendor namespace was Bluetooth SIG (1). Store builds now use this path for connected audio accessory names, addresses and model IDs. Hardware-address matching, model-specific symbols and dedicated settings-link construction are preserved where metadata is present; actual per-device settings navigation is a separate check. Permission denial or missing records falls back to Core Audio symbols and generic settings links.

Battery remains a distribution difference. With the same connected AirPods, public CoreBluetooth retrieval found no connected peripheral matching the standard Battery Service (`180F`); Device Information Service (`180A`) was present. Public power-source enumeration returned only the internal Mac battery, and public HID registry inspection exposed no battery fields. This is evidence for this device/session, not proof that standard battery services never work on other hardware. These probe-only frameworks/registry checks are not added to the application. No private battery selector, private accessory power-source API, unrestricted helper, or temporary exception is used. Store builds leave battery values unknown; direct builds retain the existing profiler report.

References: [IOBluetoothDevice](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice), [connected CoreBluetooth peripherals](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:)), [public power-source enumeration](https://developer.apple.com/documentation/iokit/1523839-iopscopypowersourcesinfo).

The actual app's sandbox GUI smoke test passed with a container home and a denied read of its external source file, covering settings reopening, native menu tracking/dismissal, fixed status-item width and destination-preview restoration. Foreground activation assertions were explicitly skipped. This is separate from physical switching and login-item testing.

## Still required before submission

- Decide whether the remaining battery-display difference is acceptable; validate Bluetooth permission denial and cached metadata across more models.
- Test actual input/output changes, volume/mute changes and physical connect/disconnect under a correctly signed store build, at an agreed time.
- Test login registration/unregistration and login execution with the intended signed bundle in its final location.
- Validate direct/store preference migration and avoid concurrent installations/login entries.
- Complete Apple Developer membership, store provisioning/signing, packaging, App Store Connect metadata and review.

References: [App Sandbox configuration](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox), [sandbox inheritance](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [App Review Guidelines 2.4.5](https://developer.apple.com/app-store/review/guidelines/).
