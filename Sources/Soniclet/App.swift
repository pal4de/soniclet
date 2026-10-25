import AppKit
import CoreAudio

@main
@MainActor
struct SonicletApp {
    private static var delegate: AppDelegate?
    static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            diagnose(roundTrip: CommandLine.arguments.contains("--verify-current-defaults"))
            return
        }
        DevicePreferences.migrateLegacyPreferences()
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let appDelegate = AppDelegate()
        delegate = appDelegate
        application.delegate = appDelegate
        application.run()
    }

    private static func diagnose(roundTrip: Bool) {
        let service = CoreAudioService()
        do {
            let devices = try service.devices()
            guard !devices.isEmpty else {
                print("No devices available. Run outside a restrictive development sandbox.")
                exit(1)
            }
            for device in devices {
                let selected = service.defaultDevice(device.key.direction) == device.objectID
                print("\(device.key.direction.rawValue): \(device.name)\(selected ? " [selected]" : "")")
            }
            if roundTrip {
                for direction in AudioDirection.allCases {
                    let current = service.defaultDevice(direction)
                    guard let device = devices.first(where: { $0.key.direction == direction && $0.objectID == current }) else {
                        throw AudioServiceError(status: -1)
                    }
                    // Set the already selected device: exercises the real write path without rerouting sound.
                    try service.setDefault(device)
                    Thread.sleep(forTimeInterval: 0.15)
                    guard service.defaultDevice(direction) == current else {
                        throw AudioServiceError(status: -1)
                    }
                    print("PASS: \(direction.rawValue) default write/readback (same device)")
                }
            }
            let volume = service.volume(service.defaultDevice(.output))
            print("Output volume: \(Int(volume.value * 100))%, adjustable=\(volume.canAdjust)")
        } catch { print(error.localizedDescription); exit(1) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusBarController(model: AudioModel())
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Soniclet")
        appMenu.autoenablesItems = false
        let settingsItem = NSMenuItem(title: L10n.text("Soniclet Settings…"),
                                      action: #selector(StatusBarController.showSettings), keyEquivalent: ",")
        settingsItem.target = statusController
        appMenu.addItem(settingsItem)
        let headphones = NSMenuItem(title: L10n.text("Bluetooth Settings…"),
                                    action: #selector(StatusBarController.showHeadphoneSettings), keyEquivalent: "")
        headphones.tag = 107
        headphones.target = statusController
        appMenu.addItem(headphones)
        let update = NSMenuItem(title: L10n.text("Check for Updates…"),
                                action: #selector(StatusBarController.checkForUpdates), keyEquivalent: "")
        update.tag = 104
        update.target = statusController
        appMenu.addItem(update)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("Quit Soniclet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.text("Window"))
        windowMenu.addItem(withTitle: L10n.text("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApplication.shared.mainMenu = menu
        statusController.update()
        if CommandLine.arguments.contains("--show-settings") { statusController.showSettings() }
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.async { self.statusController.showMenu() }
        }
        if CommandLine.arguments.contains("--show-context-menu") {
            DispatchQueue.main.async { self.statusController.showContextMenu() }
        }
        #if SETTINGS_SMOKE_TEST
        Task { await SettingsSmokeTest.run(statusController) }
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Existing windows and menus keep their native activation/tracking behavior.
        if flag || statusController.menuIsOpen { return true }
        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.async { self.statusController.showMenu() }
        } else { statusController.showSettings() }
        return true
    }
}
