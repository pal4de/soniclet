# Bluetooth battery investigation

Investigated 2026-10-26, alongside the local macOS 27.2 / SDK 27 Sandbox results in [SANDBOX.md](SANDBOX.md). No new Bluetooth scan, connection, pairing, audio switch or third-party helper installation was performed for this follow-up.

## What other applications establish

| Application | Verified evidence | What cannot be inferred |
| --- | --- | --- |
| Magic Battery, Mac App Store | Its current developer-supplied store description explicitly says headphone support uses a free **Batteries helper**, downloaded/started/stopped by the application. It separately describes standard BLE Battery Service devices. | This is not proof that its headphone reading works entirely inside the main app's Sandbox, nor disclosure of the helper's exact internal APIs. |
| ToothFairy, Mac App Store | The developer manual documents separate left/right AirPods battery percentages and limits support to reporting devices. Store version history describes battery fixes for Monterey. | The public documentation inspected does not disclose its battery API or sandbox exceptions. We have not obtained/inspected its store executable. Calling its implementation public-API-only would be speculation. |
| AirBattery, open source, distributed outside the Store | Its `BLEBattery.swift` uses CoreBluetooth scanning, reads manufacturer advertisement data, and decodes model-specific Apple payload layouts for AirPods. Its generic BLE path connects and reads standard battery characteristics. | It is not a Mac App Store precedent. A public scanning API does not turn a reverse-engineered manufacturer payload into an Apple-documented battery contract. Its implementation was inspected, not copied. |

Primary sources:

- [Magic Battery developer description on the App Store](https://apps.apple.com/in/app/magic-battery/id1240063289?mt=12), specifically the headphone helper requirement. [Developer product page](https://sascha-simon.com/apps/magic-battery) also describes BLE support.
- [ToothFairy battery manual](https://c-command.com/toothfairy/help/show-battery-status-in), [App Store listing/version history](https://apps.apple.com/us/app/toothfairy/id1191449274?mt=12). The [2021 developer support thread](https://forum.c-command.com/t/airpod-pro-battery-level-stuck/14077) confirms an OS-specific battery fix, but is historical evidence, not a current API specification.
- [AirBattery source](https://github.com/lihaoyun6/AirBattery/blob/main/AirBattery/BatteryInfo/BLEBattery.swift) and [project/distribution](https://github.com/lihaoyun6/AirBattery).

## Options for Soniclet

1. **Documented standard Battery Service.** Public CoreBluetooth can read a peripheral's standard battery characteristic where supplied. Our permission-approved connected-peripheral lookup did not return an AirPods peripheral matching Battery Service `180F`; Device Information `180A` was found. This does not prove that every AirPods state or other headphone lacks the service. Actively opening a GATT connection and discovering services was not part of that cache-only test. Adding a generic BLE browser/connection lifecycle solely for battery display would expand the current utility substantially.
2. **Manufacturer BLE advertisements.** The transport uses public `CBCentralManager` and `CBAdvertisementDataManufacturerDataKey`; decoding Apple's proprietary payload is a separate compatibility commitment. It requires scanning, freshness handling and reliable attribution to the selected Core Audio device. Nearby devices with the same name/model must not be cross-matched. Coverage in all connected, in-ear and closed-case states is unverified. This is a plausible experimental path, not a working replacement already validated on macOS 27.
3. **An optional separately distributed helper.** Magic Battery establishes a real product precedent for this architecture. Soniclet's direct-download process already reads the system profiler report outside Sandbox, so an additional helper could potentially supply the same data to the Store UI. It adds another signed/notarized application, IPC identity checks, installation/update/uninstall and stale-data handling. A named competitor's Store availability does not guarantee a new helper design will pass review. No helper or sandbox exception has been added.
4. **Retain the channel difference.** The smallest current implementation: direct/Homebrew builds show reported battery data; the Store variant preserves model icons/settings-link metadata through public cached IOBluetooth and leaves missing battery data blank.

The result is not “no other app can do it.” Some use additional software; a public-API transport with undocumented device payloads is another route. What remains unproven is equivalent AirPods battery coverage in a single sandboxed Soniclet process using only documented battery contracts. Keep that distinction explicit before choosing extra infrastructure.

Apple references: [CoreBluetooth connected peripherals](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:)), [scanning](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:)), [manufacturer advertisement data](https://developer.apple.com/documentation/corebluetooth/cbadvertisementdatamanufacturerdatakey), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
