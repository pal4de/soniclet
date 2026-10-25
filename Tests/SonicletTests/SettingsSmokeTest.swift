import AppKit
import SwiftUI

/// Runs in the actual accessory application, using only public native APIs.
@MainActor
enum SettingsSmokeTest {
    private static var allowsBackgroundFocus: Bool { CommandLine.arguments.contains("--allow-background-focus") }
    static func run(_ controller: StatusBarController) async {
        guard NSApplication.shared.activationPolicy() == .accessory else { fail("Not an accessory app") }
        controller.showSettings()
        guard let first = await settingsWindow() else { fail("Settings did not become visible, key, and active") }
        capture(first.contentView, name: "settings-test-render.png")
        if allowsBackgroundFocus && !NSApplication.shared.isActive {
            print("SKIP: key/active-window assertion; OS did not grant foreground activation")
        }
        print("PASS: first settings presentation")
        first.performClose(nil)
        NSApplication.shared.hide(nil)
        try? await Task.sleep(nanoseconds: 200_000_000)
        controller.showSettings()
        guard let second = await settingsWindow() else { fail("Background settings reopening failed") }
        controller.showSettings()
        guard await settingsWindow() != nil else { fail("Existing settings did not become key") }
        let visible = NSApplication.shared.windows.filter { $0.isVisible && $0.title == L10n.text("Soniclet Settings") }
        guard visible.count == 1, (allowsBackgroundFocus || second.isKeyWindow) else { fail("Settings window was not reused (visible=\(visible.count), key=\(second.isKeyWindow))") }
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
        UserDefaults.standard.set(MenuBarIconStyle.device.rawValue, forKey: MenuBarIconStyle.preferenceKey)
        controller.update()
        guard controller.statusItem.length == requestedWidth,
              abs((controller.statusItem.button?.frame.width ?? 0) - markWidth) <= pixelTolerance else {
            fail("Device icon mode changed the status item width")
        }
        if let originalStyle { UserDefaults.standard.set(originalStyle, forKey: MenuBarIconStyle.preferenceKey) }
        else { UserDefaults.standard.removeObject(forKey: MenuBarIconStyle.preferenceKey) }
        controller.update()
        print("PASS: fixed status item width across volume symbols and all three icon styles")
        UserDefaults.standard.set(MenuBarIconStyle.soniclet.rawValue, forKey: MenuBarIconStyle.preferenceKey)
        controller.update()
        let expectedArtwork = controller.iconView.image
        controller.showAutomaticSelectionFeedback()
        guard controller.iconView.image != nil, controller.iconView.image !== expectedArtwork else { fail("Automatic selection feedback must show a standard speaker") }
        try? await Task.sleep(nanoseconds: 2_300_000_000)
        guard controller.iconView.image === expectedArtwork,
              MenuBarIconStyle.current() == .soniclet,
              controller.statusItem.length == requestedWidth else { fail("Automatic feedback must restore artwork without changing preference or width") }
        if let originalStyle { UserDefaults.standard.set(originalStyle, forKey: MenuBarIconStyle.preferenceKey) }
        else { UserDefaults.standard.removeObject(forKey: MenuBarIconStyle.preferenceKey) }
        controller.update()
        print("PASS: temporary speaker feedback restores selected icon after two seconds without routing audio")

        let primary = controller.makeDeviceMenu()
        let deviceItems = primary.items.filter { $0.representedObject is DeviceKey }
        guard primary.items.filter({ $0.action != nil && $0.isEnabled }).allSatisfy({ $0.view == nil }),
              deviceItems.allSatisfy({ $0.target === controller && $0.state == .off && $0.image?.isValid == true && $0.toolTip != $0.title }),
              primary.item(withTag: 900)?.title == "Soniclet" else {
            fail("Selectable menu items must use native rows with visible device images")
        }
        if #available(macOS 27.0, *) {
            guard deviceItems.allSatisfy({ $0.preferredImageVisibility == .visible }) else {
                fail("Device images must explicitly stay visible on macOS 27")
            }
        }
        print("PASS: native selectable menu rows, device image visibility and no checkmarks")
        await verifyVolumeButtons()

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
                        guard let window = menu.items.compactMap({ $0.view?.window }).first,
                              let button = controller.statusItem.button,
                              let statusWindow = button.window,
                              let screen = statusWindow.screen else { fail("Native device menu did not open") }
                        for direction in AudioDirection.allCases {
                            guard let row = menu.item(withTag: direction == .output ? 112 : 113) else {
                                fail("Missing native hidden-current placeholder")
                            }
                            row.title = "stale hidden-current fixture"
                            row.isHidden = false
                        }
                        controller.update()
                        for direction in AudioDirection.allCases {
                            let row = menu.item(withTag: direction == .output ? 112 : 113)!
                            let hidden = controller.model.hiddenCurrentDevice(direction)
                            guard row.isHidden == (hidden == nil),
                                  row.title == (hidden.map { L10n.format("Current: %@", $0.name) } ?? "") else {
                                fail("Hidden-current label remained stale while the device menu was open")
                            }
                        }
                        print("PASS: hidden-current rows refresh title and visibility while the native menu remains open")
                        capture(window.contentView, name: "menu-test-render.png")
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
    private static func verifyVolumeButtons() async {
        var calls = 0
        let host = NSHostingView(rootView: VolumeStepButton(up: true, enabled: false) { calls += 1 })
        let window = NSWindow(contentRect: NSRect(x: -1000, y: -1000, width: 30, height: 30),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        func button(in view: NSView) -> NSButton? {
            (view as? NSButton) ?? view.subviews.lazy.compactMap { button(in: $0) }.first
        }
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard let native = button(in: host), !native.isEnabled,
              native.isContinuous, !native.isBordered, !native.showsBorderOnlyWhileMouseInside,
              native.toolTip == nil, (native.cell as? NSButtonCell)?.highlightsBy == .contentsCellMask,
              native.alternateImage != nil else { fail("Volume endpoints must use disabled, borderless, continuous native buttons") }
        host.rootView = VolumeStepButton(up: true, enabled: true) { calls += 1 }
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard let active = button(in: host), active.isEnabled else { fail("Volume endpoint did not react to capability changes") }
        active.performClick(nil)
        guard calls == 1 else { fail("Native volume endpoint did not send its action") }
        window.close()
        print("PASS: native volume endpoint action, press-only highlight, continuous repetition configuration and disabled state")
    }

    private static func capture(_ view: NSView?, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["SONICLET_CAPTURE_DIR"], let view,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }

    private static func settingsWindow() async -> NSWindow? {
        for _ in 0..<40 {
            if let window = NSApplication.shared.windows.first(where: {
                $0.title == L10n.text("Soniclet Settings") && $0.isVisible && (allowsBackgroundFocus || $0.isKeyWindow)
            }), (allowsBackgroundFocus || NSApplication.shared.isActive) { return window }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        print("Settings diagnostics: active=\(NSApplication.shared.isActive), windows=\(NSApplication.shared.windows.map { ($0.title, $0.isVisible, $0.isKeyWindow) })")
        return nil
    }
    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
