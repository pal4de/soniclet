import Foundation

@main
struct AudioAccessoryTests {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() throws {
        let cached = AudioAccessory.fromCachedMetadata(name: "Renamed Buds", address: "11-22-33-44-55-66", category: "Headphones", vendor: 0x004c, vendorSource: 1, product: 0x2024)
        require(cached.symbol == "airpodspro" && cached.batteryPercent == nil, "Cached SDP identifies a model without inventing battery data")
        require(AudioAccessory.match(uid: "11:22:33:44:55:66:output", name: "Old Name", in: [cached]) == cached, "Cached address matches renamed Core Audio device")
        let wrongNamespace = AudioAccessory.fromCachedMetadata(name: "Other", address: nil, category: "Headphones", vendor: 0x004c, vendorSource: 2, product: 0x2024)
        require(wrongNamespace.symbol == nil, "Vendor namespace must agree before assigning Apple symbols")
        let usb = AudioAccessory.fromCachedMetadata(name: "USB ID", address: "invalid", category: "Headphones", vendor: 0x05ac, vendorSource: 2, product: 0x2024)
        require(usb.isApple && usb.address == nil, "USB vendor namespace and malformed address handled separately")
        let data = Data(#"""
        {"SPBluetoothDataType":[{"device_connected":[
          {"Studio Headset":{"device_minorType":"Headset","device_address":"AA-BB-CC-DD-EE-FF","device_vendorID":"0x054C","device_batteryLevelMain":"60%"}},
          {"Wireless Buds":{"device_minorType":"Headphones","device_address":"11:22:33:44:55:66","device_vendorID":"0x004C","device_productID":"0x2024","device_batteryLevelLeft":"20%","device_batteryLevelRight":"80%","device_batteryLevelCase":"100%"}},
          {"Unknown Headset":{"device_minorType":"Headset","device_batteryLevelMain":"invalid"}},
          {"Keyboard":{"device_minorType":"Keyboard","device_batteryLevelMain":"100%"}}
        ],"device_not_connected":[{"Disconnected":{"device_minorType":"Headphones","device_batteryLevelMain":"100%"}}]}]}
        """#.utf8)
        let entries = try AudioAccessory.parseConnected(data)
        require(entries.count == 3, "Only connected audio accessories")
        let headset = AudioAccessory.match(uid: "Bluetooth-AABBCCDDEEFF-output", name: "Renamed", in: entries)
        require(headset?.batteryPercent == 60 && headset?.isApple == false, "Match stable hardware address before name")
        let earbuds = AudioAccessory.match(uid: "opaque-uid", name: "Wireless Buds", in: entries)
        require(earbuds?.isApple == true && earbuds?.batteryPercent == 20, "Use lower earbud value, not charging case")
        require(earbuds?.symbol == "airpodspro", "Identify renamed AirPods Pro 2 by reported product ID")
        require(entries.first { $0.name == "Unknown Headset" }?.batteryPercent == nil, "Unknown is never fabricated as zero")
        require(AudioAccessory.match(uid: "AA:BB:CC:DD:EE:FF:output", name: "Wireless Buds", in: [earbuds!]) == nil,
                "Conflicting address must not fall back to the same name")
        let duplicates = [AudioAccessory(name: "Same", address: "aabbccddeeff", isApple: false, batteryPercent: 60),
                          AudioAccessory(name: "Same", address: "112233445566", isApple: true, batteryPercent: 20)]
        require(AudioAccessory.match(uid: "opaque", name: "Same", in: duplicates) == nil, "Ambiguous names must not cross-match")
        require(AudioAccessory.match(uid: "11:22:33:44:55:66:output", name: "Same", in: duplicates)?.batteryPercent == 20, "Address disambiguates duplicate names")
        let bounds: [(String, Int?)] = [("0%", 0), ("100%", 100), ("101%", nil), ("-1%", nil)]
        for (value, expected) in bounds {
            let fixture = try JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": [["device_connected": [["Test": ["device_minorType": "Headset", "device_batteryLevelMain": value]]]]]])
            require(try AudioAccessory.parseConnected(fixture).first?.batteryPercent == expected, "Battery bounds: \(value)")
        }
        for (productID, expected) in [(UInt16(0x2002), "airpods"), (0x2013, "airpods.gen3"), (0x200A, "airpodsmax"), (0xFFFF, "")] {
            let apple = AudioAccessory(name: "Custom name", address: nil, isApple: true, batteryPercent: nil, productID: productID)
            require(apple.symbol == (expected.isEmpty ? nil : expected), "Known product families and unknown fallback")
            let other = AudioAccessory(name: "AirPods Pro", address: nil, isApple: false, batteryPercent: nil, productID: productID)
            require(other.symbol == nil, "Other vendors must never inherit Apple's product-ID mapping")
        }
        let beats: [(UInt16, String)] = [(0x2003, "beats.powerbeats3"), (0x2005, "beats.earphones"),
            (0x2006, "beats.headphones"), (0x200B, "beats.powerbeatspro"), (0x2011, "beats.studiobuds"),
            (0x2012, "beats.fit.pro"), (0x2016, "beats.studiobudsplus"), (0x2017, "beats.studio.pro")]
        for (productID, symbol) in beats {
            require(AudioAccessory(name: "Renamed", address: nil, isApple: true, batteryPercent: nil, productID: productID).symbol == symbol,
                    "Known Beats model mapping")
        }
        let speakerData = try JSONSerialization.data(withJSONObject: ["SPBluetoothDataType": [["device_connected": [
            ["Room Audio": ["device_minorType": "Loudspeaker", "device_vendorID": "0x054C", "device_batteryLevelMain": "70%"]],
            ["Keyboard": ["device_minorType": "Keyboard", "device_vendorID": "0x004C"]]
        ]]]])
        let speakers = try AudioAccessory.parseConnected(speakerData)
        require(speakers.count == 1 && speakers[0].symbol == "hifispeaker.fill" && !speakers[0].isHeadphone && speakers[0].batteryPercent == 70,
                "Bluetooth speakers retain reported battery data without becoming headphones")
        require(try AudioAccessory.parseConnected(Data("{}".utf8)).isEmpty, "Missing report degrades gracefully")
        print("PASS: connected-only accessory data, address matching, duplicate names, valid battery bounds, lower-earbud aggregation, vendor-checked AirPods/Beats and speaker classification")
    }
}
