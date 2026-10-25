import AppKit

@MainActor
enum SystemSettingsLinks {
    private static let hasHeadphonePanel = FileManager.default.fileExists(
        atPath: "/System/Library/ExtensionKit/Extensions/HeadphoneSettingsExtension.appex")

    static func headphoneTitle(isApple: Bool) -> String {
        L10n.text(isApple && hasHeadphonePanel ? "Headphone Settings…" : "Bluetooth Settings…")
    }
    static func openHeadphones(isApple: Bool) {
        open(isApple && hasHeadphonePanel ? "com.apple.HeadphoneSettings" : "com.apple.BluetoothSettings")
    }
    static func openSound() { open("com.apple.Sound-Settings.extension") }

    private static func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
