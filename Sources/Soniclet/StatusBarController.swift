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
    private(set) var currentMenu: NSMenu?
    private(set) var menuIsOpen = false
    private let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)

    init(model: AudioModel) {
        self.model = model
        self.settings = SettingsWindowController(model: model)
        let symbols = ["speaker.slash.fill", "speaker.wave.1.fill", "speaker.wave.2.fill", "speaker.wave.3.fill"]
        let widest = symbols.compactMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))?.size.width
        }.max() ?? 22
        statusItem = NSStatusBar.system.statusItem(withLength: ceil(widest) + 12)
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.setAccessibilityLabel(L10n.text("Soniclet — audio devices"))
        }
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
        if UserDefaults.standard.bool(forKey: StatusMark.preferenceKey),
           let image = StatusMark.image(volume: model.outputVolume.canAdjust ? model.outputVolume.value : nil,
                                        muted: model.outputVolume.muted) {
            statusItem.button?.image = image
        } else { displaySymbol(model.outputSymbol) }
        var tooltip = summaryLines
        if updates.release != nil { tooltip.append(updates.menuTitle) }
        statusItem.button?.toolTip = tooltip.joined(separator: "\n")
        if let item = NSApplication.shared.mainMenu?.items.first?.submenu?.item(withTag: 104) {
            item.title = updates.menuTitle
            item.isEnabled = updates.actionIsEnabled
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
            if abs(view.frame.height - height) > 0.5 { view.setFrameSize(NSSize(width: 320, height: height)) }
        }
        menu.update()
    }

    // The item's length is fixed once; every symbol is centered by NSStatusBarButton.
    func displaySymbol(_ name: String) {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApplication.shared.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showContextMenu()
        } else { showMenu() }
    }

    func makeDeviceMenu() -> NSMenu {
        model.refresh()
        let menu = baseMenu()
        let content = NSHostingView(rootView: SoundMenuContent(
            model: model, updates: updates,
            updateAction: { [weak self] in self?.checkForUpdates() },
            settingsAction: { [weak self] in self?.showSettings() },
            dismissPanel: { [weak self] in self?.dismissMenu() }
        ))
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
        menu.delegate = self
        return menu
    }

    func showMenu() { present(makeDeviceMenu()) }
    func showContextMenu() { present(makeContextMenu()) }

    private func present(_ menu: NSMenu) {
        guard let button = statusItem.button, button.window != nil else { return }
        if menuIsOpen { dismissMenu(); return }
        updates.checkIfDue()
        currentMenu = menu
        // Let the status item anchor its own menu; popUp(at:) positions a menu
        // item around the point and is unsuitable for one tall custom view.
        statusItem.menu = menu
        defer { statusItem.menu = nil; currentMenu = nil }
        button.performClick(nil)
    }

    func dismissMenu() { currentMenu?.cancelTrackingWithoutAnimation() }
    @objc func toggleMute() { model.toggleOutputMute() }

    @objc func showSettings() {
        dismissMenu()
        // Finish native menu tracking before activating a settings window or alert.
        DispatchQueue.main.async { [weak self] in self?.settings.show() }
    }

    @objc func checkForUpdates() {
        dismissMenu()
        DispatchQueue.main.async { [weak self] in self?.updates.performUserAction() }
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }
}
