import Foundation

/// Only fields reported by macOS's documented system_profiler utility are used.
/// No Bluetooth scanning, private selectors, or accessory control protocols.
struct AudioAccessory: Equatable, Sendable {
    let name: String
    let address: String?
    let isApple: Bool
    let batteryPercent: Int?
    var productID: UInt16? = nil

    var symbol: String? {
        guard isApple, let productID else { return nil }
        // Public system_profiler product IDs. No BLE packets or private selectors.
        // Family reference: https://github.com/mooons/airpods-fw/blob/main/airpods-fw
        switch productID {
        case 0x2002, 0x200F: return "airpods"
        case 0x2013, 0x2019, 0x201B: return "airpods.gen3"
        case 0x200E, 0x2014, 0x2024, 0x2027: return "airpodspro"
        case 0x200A, 0x201F, 0x202D: return "airpodsmax"
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
                          ["Headphones", "Headset"].contains(type) else { return nil }
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
                    return Self(name: name, address: address, isApple: vendor == "0x004c", batteryPercent: battery, productID: productID)
                }
            }
        }
    }

    static func readConnected() throws -> [Self] {
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
    }
}
