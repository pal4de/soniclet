import AppKit
import Combine
import SwiftUI

/// NSStatusItem owns click routing and geometry; NSMenu owns contextual behavior.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    let model: AudioModel
    let statusItem: NSStatusItem
    let popover = NSPopover()
    private let settings: SettingsWindowController
    private var observation: AnyCancellable?
    private var currentMenu: NSMenu?
    private(set) var contextMenuIsOpen = false
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
            button.setAccessibilityLabel(L10n.text("Sound Switch — audio devices"))
        }
        let hosting = NSHostingController(rootView: SoundPopover(
            model: model,
            settingsAction: { [weak self] in self?.showSettings() },
            dismissPanel: { [weak self] in self?.popover.performClose(nil) }
        ))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.animates = true
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }
        update()
    }

    var summaryLines: [String] {
        [L10n.format("%@: %@", L10n.text("Output"), model.outputName),
         L10n.format("%@: %@", L10n.text("Input"), model.inputName)]
    }

    func update() {
        displaySymbol(model.outputSymbol)
        statusItem.button?.toolTip = summaryLines.joined(separator: "\n")
        if let menu = currentMenu {
            menu.items[0].title = summaryLines[0]
            menu.items[1].title = summaryLines[1]
            menu.items[3].title = L10n.text(model.outputVolume.muted ? "Unmute Output" : "Mute Output")
            menu.items[3].isEnabled = model.outputVolume.muteElement != nil
        }
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
        } else if popover.isShown {
            popover.performClose(nil)
        } else { showPopover() }
    }

    func showPopover() {
        guard let button = statusItem.button, button.window != nil else { return }
        model.refresh()
        if let view = popover.contentViewController?.view {
            view.layoutSubtreeIfNeeded()
            // Resolve SwiftUI's size before AppKit computes the anchor position.
            let size = view.fittingSize
            popover.contentSize = NSSize(width: 320, height: max(100, size.height))
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func makeContextMenu() -> NSMenu {
        model.refresh()
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        for line in summaryLines {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let mute = NSMenuItem(title: L10n.text(model.outputVolume.muted ? "Unmute Output" : "Mute Output"),
                              action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.isEnabled = model.outputVolume.muteElement != nil
        menu.addItem(mute)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: L10n.text("Sound Switch Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let quit = NSMenuItem(title: L10n.text("Quit Sound Switch"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        return menu
    }

    func showContextMenu() {
        popover.performClose(nil)
        guard let button = statusItem.button else { return }
        let menu = makeContextMenu()
        currentMenu = menu
        button.highlight(true)
        defer { button.highlight(false); currentMenu = nil }
        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.minY), in: button)
    }

    @objc func toggleMute() { model.toggleOutputMute() }

    @objc func showSettings() {
        popover.performClose(nil)
        // Let native menu tracking finish before activating the settings window.
        DispatchQueue.main.async { [weak self] in self?.settings.show() }
    }

    func menuWillOpen(_ menu: NSMenu) { contextMenuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) { contextMenuIsOpen = false }
}
