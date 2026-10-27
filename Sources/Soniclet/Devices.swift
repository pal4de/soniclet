import Foundation
import CoreAudio

enum AudioDirection: String, Codable, CaseIterable, Sendable {
    case output, input
    var title: String { L10n.text(self == .output ? "Output" : "Input") }
    var scope: AudioObjectPropertyScope {
        self == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }
    var defaultSelector: AudioObjectPropertySelector {
        self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }
}

struct DeviceKey: Hashable, Codable, Sendable {
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
    var isAirPlay: Bool { transport == kAudioDeviceTransportTypeAirPlay }
    var isBluetooth: Bool { transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE }
}

/// Use canonical OS model/icon metadata, never the user-editable device name.
enum DeviceSymbols {
    static func headphones(modelName: String, iconFileName: String) -> String {
        let identity = (modelName + " " + iconFileName).lowercased().filter { $0.isLetter || $0.isNumber }
        guard identity.contains("airpods") else { return "headphones" }
        if identity.contains("max") { return "airpodsmax" }
        if identity.contains("pro") { return "airpodspro" }
        if ["gen3", "gen4", "3rdgeneration", "4thgeneration"].contains(where: identity.contains) || modelName.lowercased().contains("airpods 3") || modelName.lowercased().contains("airpods 4") {
            return "airpods.gen3"
        }
        return "airpods"
    }
    static func output(modelName: String, iconFileName: String) -> String? {
        let headphones = headphones(modelName: modelName, iconFileName: iconFileName)
        if headphones != "headphones" { return headphones }
        let identity = (modelName + " " + iconFileName).lowercased().filter { $0.isLetter || $0.isNumber }
        if identity.contains("homepodmini") { return "homepodmini.fill" }
        if identity.contains("homepod") { return "homepod.fill" }
        if identity.contains("appletv") { return "appletv.fill" }
        if identity.contains("display") { return "display" }
        if (modelName + " " + iconFileName).range(of: #"(?i)\b(?:beats|powerbeats)"#, options: .regularExpression) != nil {
            if identity.contains("studiobudsplus") { return "beats.studiobudsplus" }
            if identity.contains("studiobuds") { return "beats.studiobuds" }
            if identity.contains("fitpro") { return "beats.fit.pro" }
            if identity.contains("powerbeatspro") { return "beats.powerbeatspro" }
            if identity.contains("powerbeats3") { return "beats.powerbeats3" }
            if identity.contains("powerbeats") { return "beats.powerbeats" }
            if identity.contains("studiopro") { return "beats.studio.pro" }
            if identity.contains("beatsx") || identity.contains("flex") { return "beats.earphones" }
            return "beats.headphones"
        }
        return nil
    }

    static func fallback(for symbol: String) -> String {
        switch symbol {
        case "beats.studio.pro": return "beats.headphones"
        case "beats.studiobudsplus": return "beats.studiobuds"
        case "beats.fit.pro": return "earbuds"
        default:
            if symbol.hasPrefix("airpods") || symbol.hasPrefix("beats.") { return "headphones" }
            if symbol.hasPrefix("homepod") || symbol.hasPrefix("appletv") { return "airplay.audio" }
            return "speaker.wave.2.fill"
        }
    }

}

struct DevicePreference: Identifiable, Codable {
    let key: DeviceKey
    var name: String
    var symbol: String
    var isVisible: Bool
    var transport: UInt32? = nil
    var sortOrder: Int? = nil
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

    func orderedDevices(_ direction: AudioDirection) -> [DevicePreference] {
        devices.filter { $0.key.direction == direction }.sorted {
            let left = $0.sortOrder ?? Int.max
            let right = $1.sortOrder ?? Int.max
            if left != right { return left < right }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func move(_ direction: AudioDirection, from offsets: IndexSet, to destination: Int) {
        var ordered = orderedDevices(direction)
        guard !offsets.isEmpty, offsets.allSatisfy({ ordered.indices.contains($0) }),
              (0...ordered.count).contains(destination) else { return }
        let moving = offsets.map { ordered[$0] }
        for index in offsets.reversed() { ordered.remove(at: index) }
        ordered.insert(contentsOf: moving, at: destination - offsets.filter { $0 < destination }.count)
        let ranks = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.key, $0) })
        for index in devices.indices where devices[index].key.direction == direction {
            devices[index].sortOrder = ranks[devices[index].key]
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) { defaults.set(data, forKey: storageKey) }
    }
}
