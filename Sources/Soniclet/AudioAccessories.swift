import Foundation
#if MAC_APP_STORE
import IOBluetooth
#endif

/// Public system_profiler reports (direct) or cached IOBluetooth metadata (store).
/// No Bluetooth scanning, private selectors, or accessory control protocols.
struct AudioAccessory: Equatable, Sendable {
    let name: String
    let address: String?
    let isApple: Bool
    let batteryPercent: Int?
    var productID: UInt16? = nil
    var category = "Headphones"
    var isHeadphone: Bool { ["Headphones", "Headset"].contains(category) }

    var symbol: String? {
        if ["Speaker", "Loudspeaker", "CarAudio"].contains(category) { return "hifispeaker.fill" }
        guard isApple, let productID else { return nil }
        // Public system_profiler product IDs. No BLE packets or private selectors.
        // Family references: https://github.com/mooons/airpods-fw/blob/main/airpods-fw
        // https://github.com/lihaoyun6/AirBattery/blob/main/AirBattery/BatteryInfo/BLEBattery.swift
        switch productID {
        case 0x2002, 0x200F: return "airpods"
        case 0x2013, 0x2019, 0x201B: return "airpods.gen3"
        case 0x200E, 0x2014, 0x2024, 0x2027: return "airpodspro"
        case 0x200A, 0x201F, 0x202D: return "airpodsmax"
        case 0x2003: return "beats.powerbeats3"
        case 0x2005, 0x2010: return "beats.earphones"
        case 0x2006, 0x2009, 0x200C: return "beats.headphones"
        case 0x200B: return "beats.powerbeatspro"
        case 0x2011: return "beats.studiobuds"
        case 0x2012: return "beats.fit.pro"
        case 0x2016: return "beats.studiobudsplus"
        case 0x2017: return "beats.studio.pro"
        default: return nil
        }
    }

    static func match(uid: String, name: String, in entries: [Self]) -> Self? {
        let flattened = uid.lowercased().replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        if let addressed = entries.first(where: { entry in
            guard let address = entry.address else { return false }
            return flattened.contains(address)
        }) { return addressed }
        // A visible hardware address which disagrees with the report must not
        // fall back to a coincidentally identical device name.
        if uid.range(of: "(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}", options: [.regularExpression, .caseInsensitive]) != nil { return nil }
        let named = entries.filter { $0.name == name }
        return named.count == 1 ? named.first : nil
    }

    static func parseConnected(_ data: Data) throws -> [Self] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        return controllers.flatMap { controller -> [Self] in
            let connected = controller["device_connected"] as? [[String: [String: Any]]] ?? []
            return connected.flatMap { item in
                item.compactMap { name, record -> Self? in
                    guard let type = record["device_minorType"] as? String,
                          ["Headphones", "Headset", "Speaker", "Loudspeaker", "CarAudio"].contains(type) else { return nil }
                    let rawAddress = (record["device_address"] as? String ?? "").lowercased()
                    let hex = rawAddress.filter { $0.isASCII && $0.isHexDigit }
                    let address = hex.count == 12 ? hex : nil
                    func percent(_ key: String) -> Int? {
                        guard let text = record[key] as? String,
                              let value = Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)),
                              (0...100).contains(value) else { return nil }
                        return value
                    }
                    // The lower earbud value is useful without turning this into an
                    // accessory dashboard. A case-only value is never substituted.
                    let ears = [percent("device_batteryLevelLeft"), percent("device_batteryLevelRight")].compactMap { $0 }
                    let battery = percent("device_batteryLevelMain") ?? percent("device_batteryLevel") ?? ears.min()
                    let vendor = (record["device_vendorID"] as? String ?? "").lowercased()
                    let product = (record["device_productID"] as? String ?? "").lowercased()
                    let productID = UInt16(product.hasPrefix("0x") ? String(product.dropFirst(2)) : product, radix: 16)
                    return Self(name: name, address: address, isApple: vendor == "0x004c", batteryPercent: battery, productID: productID, category: type)
                }
            }
        }
    }

    static func readConnected() throws -> [Self] {
#if MAC_APP_STORE
        // Read the system cache only: no scan, SDP query, connection or pairing.
        let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return devices.filter { $0.isConnected() }.compactMap { device -> Self? in
            guard device.deviceClassMajor == kBluetoothDeviceClassMajorAudio,
                  let name = device.name, !name.isEmpty else { return nil }
            let category: String
            switch Int(device.deviceClassMinor) {
            case kBluetoothDeviceClassMinorAudioHeadset: category = "Headset"
            case kBluetoothDeviceClassMinorAudioHeadphones: category = "Headphones"
            case kBluetoothDeviceClassMinorAudioLoudspeaker: category = "Loudspeaker"
            case kBluetoothDeviceClassMinorAudioCar: category = "CarAudio"
            default: return nil
            }
            let uuid = IOBluetoothSDPUUID(uuid16: BluetoothSDPUUID16(kBluetoothSDPUUID16ServiceClassPnPInformation.rawValue))
            let record = uuid.flatMap { device.getServiceRecord(for: $0) }
            func number(_ attribute: UInt32) -> UInt16? {
                guard let value = record?.getAttributeDataElement(BluetoothSDPServiceAttributeID(attribute))?.getNumberValue()?.intValue else { return nil }
                return UInt16(exactly: value)
            }
            return fromCachedMetadata(name: name, address: device.addressString, category: category,
                vendor: number(kBluetoothSDPAttributeDeviceIdentifierVendorID.rawValue),
                vendorSource: number(kBluetoothSDPAttributeDeviceIdentifierVendorIDSource.rawValue),
                product: number(kBluetoothSDPAttributeDeviceIdentifierProductID.rawValue))
        }
#else
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-timeout", "5"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return try parseConnected(data)
#endif
    }

    /// SDP Device ID uses distinct Bluetooth SIG (1) and USB (2) vendor namespaces.
    /// Missing battery metadata stays unknown; a product ID never implies a level.
    static func fromCachedMetadata(name: String, address: String?, category: String,
                                   vendor: UInt16?, vendorSource: UInt16?, product: UInt16?) -> Self {
        let hex = (address ?? "").lowercased().filter { $0.isASCII && $0.isHexDigit }
        let apple = (vendorSource == 1 && vendor == 0x004c) || (vendorSource == 2 && vendor == 0x05ac)
        return Self(name: name, address: hex.count == 12 ? hex : nil, isApple: apple,
                    batteryPercent: nil, productID: product, category: category)
    }
}
