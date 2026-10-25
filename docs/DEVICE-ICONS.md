# Device icons

Soniclet uses the closest available SF Symbol for the actual device or device family. It does not draw brand logos or infer a model from a user-editable name. A dedicated symbol for every manufacturer/model is not available.

| Family | Identification | Presentation |
| --- | --- | --- |
| AirPods 1/2 | Apple vendor/product ID, or canonical Core Audio metadata | AirPods |
| AirPods 3/4 | Apple vendor/product ID, or canonical model/generation metadata | Short-stem AirPods symbol |
| AirPods Pro 1/2/3 | Apple vendor/product ID, or canonical metadata | AirPods Pro |
| AirPods Max | Apple vendor/product ID, or canonical metadata | AirPods Max |
| Beats Solo3 / Studio3 / Solo Pro | Apple vendor/product ID | Beats headphones |
| BeatsX / Flex | Apple vendor/product ID | Beats earphones |
| Powerbeats3 / Powerbeats Pro | Apple vendor/product ID | Respective Powerbeats family |
| Beats Studio Buds / Studio Buds+ / Fit Pro / Studio Pro | Apple vendor/product ID | Respective family when the OS supplies that symbol |
| HomePod / HomePod mini / Apple TV | Canonical Core Audio model, model UID or icon filename | Respective system symbol |
| Display audio | Canonical metadata or HDMI/DisplayPort transport | Display |
| Bluetooth speaker / car audio | Audio class in the standard connected-device report | Speaker, rather than headphone |
| Other headphones, including Sony/Bose | Public audio-stream terminal type or Bluetooth audio class | Generic headphone |
| Other USB, built-in and AirPlay routes | Public Core Audio metadata and transport | Standard speaker/computer/microphone/AirPlay fallback |

Identification uses documented Core Audio properties and the existing macOS `system_profiler SPBluetoothDataType -json` report. That report also supplies battery data, when present. No extra scan, Bluetooth permission, private framework, control protocol or dependency is introduced. Unknown product IDs and unavailable symbols fall back to a device-family or generic symbol. A battery percentage is shown only when actually reported.

The connected AirPods Pro 2 (USB-C) was verified locally: Core Audio returned no model/icon metadata, but Apple's vendor ID and product ID `0x2024` in the standard report resolved it to `airpodspro`. Other family mappings are covered by fixtures, not a claim that every physical model was tested. Report requests are refreshed on connection changes; stale cancelled results cannot overwrite a newer connection.

Product-ID reference observations: [airpods-fw model table](https://github.com/mooons/airpods-fw/blob/main/airpods-fw), [AirBattery model-ID notes](https://github.com/lihaoyun6/AirBattery/blob/main/AirBattery/BatteryInfo/BLEBattery.swift), and [Theengs decoder model IDs](https://github.com/theengs/decoder/blob/development/src/devices/APPLEAIRPODS_json.h). Soniclet only uses these identification facts; it does not include their protocol or scanning implementations.

System-icon mode uses SF Symbols effects for actual type changes and explicit mute changes (Magic Replace on macOS 15+, standard replace on macOS 14). Same-shape and volume-only changes are immediate. The user's Soniclet-mark selection is preserved across devices. Reduce Motion disables transitions.
