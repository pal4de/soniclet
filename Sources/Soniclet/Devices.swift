import Foundation
import CoreAudio

enum AudioDirection: String, Codable, CaseIterable {
    case output, input
    var title: String { L10n.text(self == .output ? "Output" : "Input") }
    var scope: AudioObjectPropertyScope {
        self == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }
    var defaultSelector: AudioObjectPropertySelector {
        self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }
}

struct DeviceKey: Hashable, Codable {
    let uid: String
    let direction: AudioDirection
}

struct AudioDevice: Identifiable {
    let objectID: AudioDeviceID
    let key: DeviceKey
    let name: String
    let symbol: String
    let isBuiltIn: Bool
    var transport: UInt32 = 0
    var id: DeviceKey { key }
    var isBluetooth: Bool { transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE }
}

struct DevicePreference: Identifiable, Codable {
    let key: DeviceKey
    var name: String
    var symbol: String
    var isVisible: Bool
    var transport: UInt32? = nil
    var id: DeviceKey { key }
}

/// Preferences contain stable UIDs, never the transient Core Audio object IDs.
final class DevicePreferences {
    /// Import only our earlier development build's visibility data, without
    /// overriding Soniclet settings or copying unrelated application defaults.
    static func migrateLegacyPreferences(in defaults: UserDefaults = .standard,
                                         from domain: String = "local.sound-switch.app") {
        let key = "devicePreferences.v1"
        guard defaults.object(forKey: key) == nil,
              let data = defaults.persistentDomain(forName: domain)?[key] as? Data,
              (try? JSONDecoder().decode([DevicePreference].self, from: data)) != nil else { return }
        defaults.set(data, forKey: key)
    }

    private let defaults: UserDefaults
    private let storageKey = "devicePreferences.v1"
    private(set) var devices: [DevicePreference]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        devices = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([DevicePreference].self, from: $0) } ?? []
    }

    func synchronize(_ discovered: [AudioDevice]) {
        let connected = Set(discovered.map(\.key))
        let previousCount = devices.count
        // AirPlay's HAL endpoints can have session-specific UIDs. Do not retain
        // disconnected phantom routes. The symbol check migrates legacy records.
        devices.removeAll {
            let isAirPlay = $0.transport == kAudioDeviceTransportTypeAirPlay ||
                ($0.transport == nil && $0.symbol == "airplay.audio")
            return isAirPlay && !connected.contains($0.key)
        }
        var changed = devices.count != previousCount
        for device in discovered {
            if let index = devices.firstIndex(where: { $0.key == device.key }) {
                if devices[index].name != device.name || devices[index].symbol != device.symbol || devices[index].transport != device.transport {
                    devices[index].name = device.name
                    devices[index].symbol = device.symbol
                    devices[index].transport = device.transport
                    changed = true
                }
            } else {
                devices.append(DevicePreference(key: device.key, name: device.name,
                                                symbol: device.symbol, isVisible: true, transport: device.transport))
                changed = true
            }
        }
        if changed { save() }
    }

    func isVisible(_ key: DeviceKey) -> Bool {
        devices.first(where: { $0.key == key })?.isVisible ?? true
    }

    func setVisible(_ visible: Bool, for key: DeviceKey) {
        guard let index = devices.firstIndex(where: { $0.key == key }) else { return }
        devices[index].isVisible = visible
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) { defaults.set(data, forKey: storageKey) }
    }
}
