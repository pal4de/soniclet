import AppKit
import SwiftUI

/// Native SwiftUI settings hosting on macOS 26+, with a small AppKit fallback.
@MainActor
final class SettingsWindowController {
    private let model: AudioModel
    private var nativeOpen: (() -> Void)?
    private var fallbackWindow: NSWindow?

    init(model: AudioModel) {
        self.model = model
        if #available(macOS 26, *) {
            let representation = NSHostingSceneRepresentation {
                Settings {
                    DeviceSettingsView(model: model)
                        .navigationTitle(L10n.text("Sound Switch Settings"))
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
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = L10n.text("Sound Switch Settings")
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: DeviceSettingsView(model: model))
            window.center()
            fallbackWindow = window
        }
        fallbackWindow?.makeKeyAndOrderFront(nil)
    }
}
