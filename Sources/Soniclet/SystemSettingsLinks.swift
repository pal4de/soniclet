import AppKit

@MainActor
enum SystemSettingsLinks {
    private static let hasHeadphonePanel = FileManager.default.fileExists(
        atPath: "/System/Library/ExtensionKit/Extensions/HeadphoneSettingsExtension.appex")

    static func headphoneTitle(accessory: AudioAccessory?) -> String {
        guard hasHeadphonePanel, let accessory else { return L10n.text("Bluetooth Settings…") }
        return L10n.format("“%@” Settings…", accessory.name)
    }
    static func openHeadphones(accessory: AudioAccessory?) {
        guard hasHeadphonePanel, let address = accessory?.address, address.count == 12 else {
            open("com.apple.BluetoothSettings")
            return
        }
        // The settings extension has one personality per connected accessory.
        let pairs = stride(from: 0, to: 12, by: 2).map { offset in
            let start = address.index(address.startIndex, offsetBy: offset)
            return String(address[start..<address.index(start, offsetBy: 2)]).uppercased()
        }
        open("com.apple.HeadphoneSettings*\(pairs.joined(separator: "-"))")
    }
    static func openSound() { open("com.apple.Sound-Settings.extension") }

    private static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
