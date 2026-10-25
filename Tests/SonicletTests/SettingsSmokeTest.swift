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

        let originalStyle = UserDefaults.standard.object(forKey: MenuBarIconStyle.preferenceKey)
        UserDefaults.standard.set(MenuBarIconStyle.system.rawValue, forKey: MenuBarIconStyle.preferenceKey)
        controller.update()
        try? await Task.sleep(nanoseconds: 50_000_000)
        let requestedWidth = controller.statusItem.length
        // Native symbol/non-symbol buttons can align their bounds to adjacent
        // half-points. The status item's allocated length must remain identical.
        let pixelTolerance = 1 / (controller.statusItem.button?.window?.backingScaleFactor ?? 2) + 0.01
        let expectedWidth = controller.statusItem.button?.frame.width ?? 0
        guard expectedWidth > 0 else { fail("Status button has no width") }
        for name in ["speaker.slash.fill", "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill"] {
            controller.displaySymbol(name)
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard controller.statusItem.length == requestedWidth, abs((controller.statusItem.button?.frame.width ?? 0) - expectedWidth) <= pixelTolerance else {
                fail("Status item width changed for \(name): \(controller.statusItem.button?.frame.width ?? 0) vs \(expectedWidth), requested \(requestedWidth)")
            }
        }
        UserDefaults.standard.set(MenuBarIconStyle.soniclet.rawValue, forKey: MenuBarIconStyle.preferenceKey)
        controller.update()
        guard controller.iconView.image?.isTemplate == true,
              controller.iconView.image?.size == NSSize(width: 19, height: 19),
              controller.statusItem.length == requestedWidth,
              abs((controller.statusItem.button?.frame.width ?? 0) - expectedWidth) <= pixelTolerance else {
            fail("App-icon style: template=\(controller.iconView.image?.isTemplate ?? false), size=\(String(describing: controller.iconView.image?.size)), width=\(controller.statusItem.button?.frame.width ?? 0), expected=\(expectedWidth), pref=\(MenuBarIconStyle.current().rawValue)")
        }
        let markWidth = controller.statusItem.button?.frame.width ?? 0
        for level in 0...3 {
            controller.iconView.image = StatusMark.makeImage(level: level)
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard controller.statusItem.length == requestedWidth,
                  abs((controller.statusItem.button?.frame.width ?? 0) - markWidth) <= pixelTolerance else {
                fail("Waveform levels changed the status item width")
            }
        }
        if let originalStyle { UserDefaults.standard.set(originalStyle, forKey: MenuBarIconStyle.preferenceKey) }
        else { UserDefaults.standard.removeObject(forKey: MenuBarIconStyle.preferenceKey) }
        controller.update()
        print("PASS: fixed status item width across volume symbols and both icon styles")

        let menu = controller.makeContextMenu()
        guard menu.items.count == 8,
              !menu.items[0].isEnabled, menu.items[0].action == nil,
              !menu.items[1].isEnabled, menu.items[1].action == nil,
              menu.items[0].title == controller.summaryLines[0],
              menu.items[1].title == controller.summaryLines[1],
              menu.items[3].isEnabled == (controller.model.outputVolume.muteElement != nil),
              menu.items[5].action == #selector(StatusBarController.showSettings),
              menu.items[6].action == #selector(StatusBarController.checkForUpdates),
              menu.items[7].action == #selector(NSApplication.terminate(_:)),
              controller.statusItem.button?.toolTip == controller.summaryLines.joined(separator: "\n") else {
            fail("Context menu or tooltip mismatch")
        }
        print("PASS: native context menu, read-only summaries, mute availability, settings/quit, tooltip")

        for context in [false, true, false] {
            var inspected = false
            let timer = Timer(timeInterval: 0.25, repeats: false) { _ in
                MainActor.assumeIsolated {
                    guard controller.menuIsOpen, let menu = controller.currentMenu,
                          controller.statusItem.menu === menu else { fail("Native menu lost its permanent attachment") }
                    if context {
                        guard menu.items.count == 8, menu.items.first?.view == nil,
                              menu.items.first?.title == controller.summaryLines[0] else { fail("Wrong right-click menu") }
                    } else {
                        guard let window = menu.items.first?.view?.window,
                              let button = controller.statusItem.button,
                              let statusWindow = button.window,
                              let screen = statusWindow.screen else { fail("Native device menu did not open") }
                        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
                        guard window.frame.maxY <= anchor.minY + 12,
                              window.frame.minY >= screen.visibleFrame.minY,
                              window.frame.minX >= screen.frame.minX,
                              window.frame.maxX <= screen.frame.maxX else {
                            fail("Menu positioning: menu=\(window.frame), anchor=\(anchor), screen=\(screen.frame)")
                        }
                    }
                    inspected = true
                    controller.dismissMenu()
                }
            }
            RunLoop.main.add(timer, forMode: .eventTracking)
            RunLoop.main.add(timer, forMode: .common)
            if context { controller.showContextMenu() } else { controller.showMenu() }
            guard inspected, !controller.menuIsOpen, controller.statusItem.menu != nil else {
                fail("Native menu did not finish tracking or keep its attachment")
            }
        }
        print("PASS: permanent NSMenu attachment, primary/context switching, on-screen positioning and repeated dismissal/reopening")
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
