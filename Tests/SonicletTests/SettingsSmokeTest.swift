import AppKit
import SwiftUI

/// Runs in the actual accessory application, using only public native APIs.
@MainActor
enum SettingsSmokeTest {
    static func run(_ controller: StatusBarController) async {
        guard NSApplication.shared.activationPolicy() == .accessory else { fail("Not an accessory app") }
        controller.showSettings()
        guard let first = await settingsWindow() else { fail("Settings did not become visible, key, and active") }
        print("PASS: first settings presentation")
        first.performClose(nil)
        NSApplication.shared.hide(nil)
        try? await Task.sleep(nanoseconds: 200_000_000)
        controller.showSettings()
        guard let second = await settingsWindow() else { fail("Background settings reopening failed") }
        controller.showSettings()
        guard await settingsWindow() != nil else { fail("Existing settings did not become key") }
        let visible = NSApplication.shared.windows.filter { $0.isVisible && $0.title == L10n.text("Soniclet Settings") }
        guard visible.count == 1, second.isKeyWindow else { fail("Settings window was not reused (visible=\(visible.count), key=\(second.isKeyWindow))") }
        print("PASS: background reopening and settings window reuse")
        second.performClose(nil)

        let requestedWidth = controller.statusItem.length
        let expectedWidth = controller.statusItem.button?.frame.width ?? 0
        guard expectedWidth > 0 else { fail("Status button has no width") }
        for name in ["speaker.slash.fill", "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill"] {
            controller.displaySymbol(name)
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard abs((controller.statusItem.button?.frame.width ?? 0) - expectedWidth) < 0.5 else {
                fail("Status item width changed for \(name): \(controller.statusItem.button?.frame.width ?? 0) vs \(expectedWidth), requested \(requestedWidth)")
            }
        }
        controller.update()
        print("PASS: fixed status item width across all volume symbols")

        let menu = controller.makeContextMenu()
        guard menu.items.count == 7,
              !menu.items[0].isEnabled, menu.items[0].action == nil,
              !menu.items[1].isEnabled, menu.items[1].action == nil,
              menu.items[0].title == controller.summaryLines[0],
              menu.items[1].title == controller.summaryLines[1],
              menu.items[3].isEnabled == (controller.model.outputVolume.muteElement != nil),
              menu.items[5].action == #selector(StatusBarController.showSettings),
              menu.items[6].action == #selector(NSApplication.terminate(_:)),
              controller.statusItem.button?.toolTip == controller.summaryLines.joined(separator: "\n") else {
            fail("Context menu or tooltip mismatch")
        }
        print("PASS: native context menu, read-only summaries, mute availability, settings/quit, tooltip")

        controller.showPopover()
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard controller.popover.isShown,
              let panel = controller.popover.contentViewController?.view.window,
              let button = controller.statusItem.button,
              let statusWindow = button.window,
              let screen = statusWindow.screen else { fail("Popover did not open") }
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard panel.frame.maxY <= anchor.minY + 2,
              panel.frame.minY >= screen.visibleFrame.minY,
              panel.frame.minX >= screen.frame.minX,
              panel.frame.maxX <= screen.frame.maxX else {
            fail("Popover positioning: panel=\(panel.frame), anchor=\(anchor), screen=\(screen.frame)")
        }
        print("PASS: popover is below the menu bar and within the screen")
        controller.popover.performClose(nil)
        fflush(stdout)
        NSApplication.shared.terminate(nil)
    }
    private static func settingsWindow() async -> NSWindow? {
        for _ in 0..<40 {
            if let window = NSApplication.shared.windows.first(where: {
                $0.title == L10n.text("Soniclet Settings") && $0.isVisible && $0.isKeyWindow
            }), NSApplication.shared.isActive { return window }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }
    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
