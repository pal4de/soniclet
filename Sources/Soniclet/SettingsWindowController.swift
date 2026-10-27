import AppKit
import SwiftUI

/// Native SwiftUI settings hosting on macOS 26+, with a small AppKit fallback.
@MainActor
final class SettingsWindowController {
    private let model: AudioModel
    private let updates: UpdateChecker
    private var nativeOpen: (() -> Void)?
    private var fallbackWindow: NSWindow?

    init(model: AudioModel, updates: UpdateChecker) {
        self.model = model
        self.updates = updates
        if #available(macOS 26, *) {
            let representation = NSHostingSceneRepresentation {
                Settings {
                    DeviceSettingsView(model: model, updates: updates)
                        .navigationTitle(L10n.text("Soniclet Settings"))
                }
                .windowResizability(.contentSize)
            }
            NSApplication.shared.addSceneRepresentation(representation)
            nativeOpen = { representation.environment.openSettings() }
        }
    }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let nativeOpen {
            nativeOpen()
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        if fallbackWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L10n.text("Soniclet Settings")
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: DeviceSettingsView(model: model, updates: updates))
            window.center()
            fallbackWindow = window
        }
        fallbackWindow?.makeKeyAndOrderFront(nil)
    }
}
