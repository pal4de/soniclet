import AppKit
import Combine
import SwiftUI

/// AppKit owns status-item geometry, menu tracking, outside clicks and Escape.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    let model: AudioModel
    let updates = UpdateChecker()
    let statusItem: NSStatusItem
    private let settings: SettingsWindowController
    private var observations = Set<AnyCancellable>()
    private let attachedMenu = NSMenu()
    private var forcedContext: Bool?
    var currentMenu: NSMenu? { menuIsOpen ? attachedMenu : nil }
    private(set) var menuIsOpen = false

    init(model: AudioModel) {
        self.model = model
        self.settings = SettingsWindowController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel(L10n.text("Soniclet — audio devices"))
        }
        attachedMenu.autoenablesItems = false
        attachedMenu.delegate = self
        statusItem.menu = attachedMenu
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }.store(in: &observations)
        updates.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }.store(in: &observations)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.update() }
            }.store(in: &observations)
        update()
        updates.checkIfDue()
    }

    var summaryLines: [String] {
        [L10n.format("%@: %@", L10n.text("Output"), model.outputName),
         L10n.format("%@: %@", L10n.text("Input"), model.inputName)]
    }

    func update() {
        if MenuBarIconStyle.current() == .soniclet,
           let image = StatusMark.image(volume: model.outputVolume.canAdjust ? model.outputVolume.value : nil,
                                        muted: model.outputVolume.muted) {
            statusItem.button?.image = image
        } else { displaySymbol(model.outputSymbol, value: model.outputSymbolValue) }
        var tooltip = summaryLines
        if updates.release != nil { tooltip.append(updates.menuTitle) }
        statusItem.button?.toolTip = tooltip.joined(separator: "\n")
        if let item = NSApplication.shared.mainMenu?.items.first?.submenu?.item(withTag: 104) {
            item.title = updates.menuTitle
            item.isEnabled = updates.actionIsEnabled
        }
        if let item = NSApplication.shared.mainMenu?.items.first?.submenu?.item(withTag: 107) {
            item.title = SystemSettingsLinks.headphoneTitle(isApple: model.hasAppleHeadphones)
            item.isHidden = model.bluetoothOutputs.isEmpty
        }
        guard let menu = currentMenu else { return }
        menu.item(withTag: 101)?.title = summaryLines[0]
        menu.item(withTag: 102)?.title = summaryLines[1]
        menu.item(withTag: 103)?.title = L10n.text(model.outputVolume.muted ? "Unmute Output" : "Mute Output")
        menu.item(withTag: 103)?.isEnabled = model.outputVolume.muteElement != nil
        menu.item(withTag: 104)?.title = updates.menuTitle
        menu.item(withTag: 104)?.isEnabled = updates.actionIsEnabled
        if let view = menu.items.first?.view {
            let height = view.fittingSize.height
            if abs(view.frame.height - height) > 0.5 {
                view.setFrameSize(NSSize(width: 304, height: height))
                menu.update() // Re-layout only; menuNeedsUpdate leaves open contents intact.
            }
        }
    }

    // The item's length is fixed once; every symbol is centered by NSStatusBarButton.
    func displaySymbol(_ name: String, value: Double = 1) {
        let image = NSImage(systemSymbolName: name, variableValue: value, accessibilityDescription: nil)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func makeDeviceMenu() -> NSMenu {
        model.refresh()
        let menu = baseMenu()
        let content = NSHostingView(rootView: SoundMenuContent(
            model: model, updates: updates,
            updateAction: { [weak self] in self?.checkForUpdates() },
            settingsAction: { [weak self] in self?.showSettings() },
            dismissPanel: { [weak self] in self?.dismissMenu() }
        ).environment(\.controlActiveState, .active))
        content.sizingOptions = [.intrinsicContentSize]
        content.setFrameSize(content.fittingSize)
        let item = NSMenuItem()
        item.view = content
        menu.addItem(item)
        return menu
    }

    func makeContextMenu() -> NSMenu {
        model.refresh()
        let menu = baseMenu()
        for (index, line) in summaryLines.enumerated() {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.tag = 101 + index
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let mute = NSMenuItem(title: L10n.text(model.outputVolume.muted ? "Unmute Output" : "Mute Output"),
                              action: #selector(toggleMute), keyEquivalent: "")
        mute.tag = 103
        mute.target = self
        mute.isEnabled = model.outputVolume.muteElement != nil
        menu.addItem(mute)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L10n.text("Soniclet Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let update = NSMenuItem(title: updates.menuTitle, action: #selector(checkForUpdates), keyEquivalent: "")
        update.tag = 104
        update.target = self
        update.isEnabled = updates.actionIsEnabled
        menu.addItem(update)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L10n.text("Quit Soniclet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        return menu
    }

    private func baseMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

    func showMenu() {
        forcedContext = false
        statusItem.button?.performClick(nil)
    }

    func showContextMenu() {
        forcedContext = true
        statusItem.button?.performClick(nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === attachedMenu, !menuIsOpen else { return }
        let event = NSApplication.shared.currentEvent
        let context = forcedContext ?? (event?.type == .rightMouseDown || event?.type == .rightMouseUp ||
                                        event?.modifierFlags.contains(.control) == true)
        updates.checkIfDue()
        model.refreshAccessoriesIfNeeded()
        let content = context ? makeContextMenu() : makeDeviceMenu()
        menu.removeAllItems()
        for item in content.items {
            content.removeItem(item)
            menu.addItem(item)
        }
    }

    func dismissMenu() { currentMenu?.cancelTrackingWithoutAnimation() }
    @objc func toggleMute() { model.toggleOutputMute() }

    @objc func showSettings() {
        dismissMenu()
        // Finish native menu tracking before activating a settings window or alert.
        DispatchQueue.main.async { [weak self] in self?.settings.show() }
    }

    @objc func showHeadphoneSettings() {
        dismissMenu()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            SystemSettingsLinks.openHeadphones(isApple: self.model.hasAppleHeadphones)
        }
    }

    @objc func checkForUpdates() {
        dismissMenu()
        DispatchQueue.main.async { [weak self] in self?.updates.performUserAction() }
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false; forcedContext = nil }
}
