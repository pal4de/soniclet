import Foundation
import CoreAudio

struct AudioServiceError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { L10n.format("Audio operation failed (%d). Check the device connection and try again.", status) }
}

struct AudioProperty {
    let object: AudioObjectID
    var address: AudioObjectPropertyAddress
}

struct OutputVolume {
    let value: Float
    let channels: [UInt32]
    let muteElement: UInt32?
    let muted: Bool
    var canAdjust: Bool { !channels.isEmpty && value.isFinite }
}

/// Only reads device metadata and changes system defaults / hardware controls.
/// No audio capture, virtual drivers, processing, or private APIs.
final class CoreAudioService {
    private var listeners: [(AudioProperty, AudioObjectPropertyListenerBlock)] = []
    private let callbackQueue = DispatchQueue(label: "Soniclet.audio-notifications")

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private func scalar<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = Self.address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value)
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private func iconFileName(_ object: AudioObjectID) -> String {
        var property = Self.address(kAudioDevicePropertyIcon)
        var value: Unmanaged<CFURL>?
        var size = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value) == noErr,
              let value else { return "" }
        return (value.takeRetainedValue() as URL).lastPathComponent
    }

    private func canonicalOutputSymbol(_ device: AudioDeviceID) -> String? {
        let model = [string(device, kAudioObjectPropertyModelName), string(device, kAudioDevicePropertyModelUID)]
            .compactMap { $0 }.joined(separator: " ")
        return DeviceSymbols.output(modelName: model, iconFileName: iconFileName(device))
    }

    func defaultDevice(_ direction: AudioDirection) -> AudioDeviceID {
        scalar(AudioObjectID(kAudioObjectSystemObject), Self.address(direction.defaultSelector), initial: AudioDeviceID(0)) ?? 0
    }

    func devices() throws -> [AudioDevice] {
        var property = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size)
        guard status == noErr else { throw AudioServiceError(status: status) }
        guard size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        status = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { throw AudioServiceError(status: status) }
        var result: [AudioDevice] = []
        for id in ids {
            guard let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { continue }
            let transport = scalar(id, Self.address(kAudioDevicePropertyTransportType), initial: UInt32(0)) ?? 0
            for direction in AudioDirection.allCases where channelCount(id, direction) > 0 {
                // Utility-only virtual endpoints (e.g. Teams sharing audio) must not be offered as system defaults.
                let eligible = scalar(id, Self.address(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: direction.scope), initial: UInt32(0)) ?? 0
                guard eligible != 0 else { continue }
                let symbol: String
                if direction == .input {
                    symbol = transport == kAudioDeviceTransportTypeBuiltIn ? "laptopcomputer" : "mic"
                } else if let canonical = canonicalOutputSymbol(id) {
                    symbol = canonical
                } else if hasHeadphoneStream(id) {
                    symbol = "headphones"
                } else {
                    switch transport {
                    case kAudioDeviceTransportTypeBuiltIn: symbol = "laptopcomputer"
                    case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: symbol = "display"
                    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: symbol = "headphones"
                    case kAudioDeviceTransportTypeAirPlay: symbol = "airplay.audio"
                    default: symbol = "speaker.wave.2.fill"
                    }
                }
                result.append(AudioDevice(objectID: id, key: DeviceKey(uid: uid, direction: direction),
                                          name: name, symbol: symbol, isBuiltIn: transport == kAudioDeviceTransportTypeBuiltIn, transport: transport))
            }
        }
        return result.sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func hasHeadphoneStream(_ device: AudioDeviceID) -> Bool {
        var property = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr, size >= MemoryLayout<AudioStreamID>.size else { return false }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        let status = streams.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(device, &property, 0, nil, &size, $0.baseAddress!)
        }
        guard status == noErr else { return false }
        return streams.contains {
            scalar($0, Self.address(kAudioStreamPropertyTerminalType), initial: UInt32(0)) == kAudioStreamTerminalTypeHeadphones
        }
    }

    private func channelCount(_ device: AudioDeviceID, _ direction: AudioDirection) -> Int {
        var property = Self.address(kAudioDevicePropertyStreamConfiguration, scope: direction.scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, pointer) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(pointer.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    func setDefault(_ device: AudioDevice) throws {
        try write(AudioObjectID(kAudioObjectSystemObject), Self.address(device.key.direction.defaultSelector), device.objectID)
    }

    private func write<T>(_ device: AudioObjectID, _ property: AudioObjectPropertyAddress, _ newValue: T) throws {
        var property = property
        var value = newValue
        let status = withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
        guard status == noErr else { throw AudioServiceError(status: status) }
    }

    private func settable(_ device: AudioObjectID, _ property: AudioObjectPropertyAddress) -> Bool {
        var property = property
        var value: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &property, &value) == noErr && value.boolValue
    }

    func volume(_ device: AudioDeviceID) -> OutputVolume {
        let scope = kAudioObjectPropertyScopeOutput
        let selector = kAudioDevicePropertyVolumeScalar
        var channels: [UInt32] = []
        let main = Self.address(selector, scope: scope)
        if settable(device, main), scalar(device, main, initial: Float(0)) != nil { channels = [0] }
        else {
            // Only offer a stereo slider when both channels support it; never adjust one side alone.
            let stereo: [UInt32] = [1, 2]
            if stereo.allSatisfy({ settable(device, Self.address(selector, scope: scope, element: $0)) && scalar(device, Self.address(selector, scope: scope, element: $0), initial: Float(0)) != nil }) {
                channels = stereo
            }
        }
        let values = channels.compactMap { scalar(device, Self.address(selector, scope: scope, element: $0), initial: Float(0)) }
        let value = values.isEmpty ? 0 : values.reduce(0, +) / Float(values.count)
        let muteProperty = Self.address(kAudioDevicePropertyMute, scope: scope)
        let muted = scalar(device, muteProperty, initial: UInt32(0)) ?? 0
        return OutputVolume(value: value, channels: channels,
                            muteElement: settable(device, muteProperty) ? 0 : nil, muted: muted != 0)
    }

    func setVolume(_ value: Float, on device: AudioDeviceID, controls: OutputVolume) throws {
        for channel in controls.channels {
            try write(device, Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: channel),
                      max(0, min(1, value)))
        }
        if value > 0, controls.muted, let element = controls.muteElement {
            try write(device, Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: element), UInt32(0))
        }
    }

    func setMuted(_ muted: Bool, on device: AudioDeviceID, controls: OutputVolume) throws {
        guard let element = controls.muteElement else { throw AudioServiceError(status: kAudioHardwareUnsupportedOperationError) }
        try write(device, Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: element), UInt32(muted ? 1 : 0))
    }

    func observe(outputID: AudioDeviceID, onChange: @escaping () -> Void) {
        stopObserving()
        let system = AudioObjectID(kAudioObjectSystemObject)
        var properties = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                          kAudioHardwarePropertyDefaultInputDevice].map { AudioProperty(object: system, address: Self.address($0)) }
        if outputID != 0 {
            for element: UInt32 in [0, 1, 2] {
                properties.append(AudioProperty(object: outputID, address: Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: element)))
            }
            properties.append(AudioProperty(object: outputID, address: Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)))
            properties.append(AudioProperty(object: outputID, address: Self.address(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)))
            properties.append(AudioProperty(object: outputID, address: Self.address(kAudioDevicePropertyJackIsConnected, scope: kAudioObjectPropertyScopeOutput)))
        }
        for var property in properties {
            guard AudioObjectHasProperty(property.object, &property.address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            if AudioObjectAddPropertyListenerBlock(property.object, &property.address, callbackQueue, block) == noErr {
                listeners.append((property, block))
            }
        }
    }

    func stopObserving() {
        for (var property, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(property.object, &property.address, callbackQueue, block)
        }
        listeners.removeAll()
    }
    deinit { stopObserving() }
}
