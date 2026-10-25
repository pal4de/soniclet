import AppKit
import Combine
import SwiftUI
import QuartzCore
import Symbols

/// AppKit owns status-item geometry, menu tracking, outside clicks and Escape.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    let model: AudioModel
    let updates = UpdateChecker()
    let statusItem: NSStatusItem
    let iconView = StatusIconView(frame: NSRect(x: 0, y: 0, width: 22, height: 20))
    private let settings: SettingsWindowController
    private var observations = Set<AnyCancellable>()
    private let attachedMenu = NSMenu()
    private var forcedContext: Bool?
    private var displayedIconKey: String?
    private var displayedSymbolName: String?
    private struct IconContext: Equatable {
        let output: UInt32
        let muted: Bool
        let style: MenuBarIconStyle
        let family: String?
    }
    private var displayedContext: IconContext?
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
            iconView.imageScaling = .scaleProportionallyDown
            iconView.contentTintColor = .labelColor
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            iconView.setAccessibilityElement(false)
            button.addSubview(iconView)
            iconView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 22),
                iconView.heightAnchor.constraint(equalToConstant: 20)
            ])
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
        let style = MenuBarIconStyle.current()
        let context = IconContext(output: model.outputID, muted: model.outputVolume.muted, style: style,
                                  family: model.devices.first { $0.key.direction == .output && $0.objectID == model.outputID }.map { model.symbol(for: $0) })
        let transition = displayedContext != context
        displayedContext = context
        if style == .soniclet,
           let image = StatusMark.image(volume: model.outputVolume.canAdjust ? model.outputVolume.value : nil,
                                        muted: model.outputVolume.muted) {
            let level = StatusMark.level(volume: model.outputVolume.canAdjust ? model.outputVolume.value : nil, muted: model.outputVolume.muted)
            setStatusImage(image, key: "soniclet:\(level)", allowTransition: transition)
        } else { displaySymbol(style.symbol(device: model.outputSymbol, volume: model.volumeSymbol), value: model.outputSymbolValue, animated: transition) }
        var tooltip = summaryLines
        if updates.release != nil { tooltip.append(updates.menuTitle) }
        statusItem.button?.toolTip = tooltip.joined(separator: "\n")
        if let item = NSApplication.shared.mainMenu?.items.first?.submenu?.item(withTag: 104) {
            item.title = updates.menuTitle
            item.isEnabled = updates.actionIsEnabled
        }
        if let item = NSApplication.shared.mainMenu?.items.first?.submenu?.item(withTag: 107) {
            item.title = SystemSettingsLinks.headphoneTitle(accessory: model.appleHeadphones)
            item.isHidden = model.bluetoothOutputs.isEmpty
        }
        guard let menu = currentMenu else { return }
        menu.item(withTag: 101)?.title = summaryLines[0]
        menu.item(withTag: 102)?.title = summaryLines[1]
        menu.item(withTag: 103)?.title = L10n.text(model.outputVolume.muted ? "Unmute Output" : "Mute Output")
        menu.item(withTag: 103)?.isEnabled = model.outputVolume.muteElement != nil
        menu.item(withTag: 104)?.title = updates.menuTitle
        menu.item(withTag: 104)?.isEnabled = updates.actionIsEnabled
        if menu.item(withTag: 900) != nil {
            let expected = AudioDirection.allCases.flatMap { model.visibleDevices($0).map(\.key) }
            let actual = menu.items.compactMap { $0.representedObject as? DeviceKey }
            if actual != expected {
                replaceContents(of: menu, with: makeDeviceMenu())
            } else {
                for item in menu.items {
                    guard let key = item.representedObject as? DeviceKey,
                          let device = model.devices.first(where: { $0.key == key }) else { continue }
                    configureDevice(item, device: device)
                }
                menu.item(withTag: 110)?.isHidden = model.outputIsAirPlay
                menu.item(withTag: 111)?.isHidden = model.errorMessage == nil
                if let item = menu.item(withTag: 107) {
                    item.title = SystemSettingsLinks.headphoneTitle(accessory: model.appleHeadphones)
                }
            }
            for view in menu.items.compactMap(\.view) {
                view.layoutSubtreeIfNeeded()
                view.setFrameSize(view.fittingSize)
            }
            menu.update()
        }
    }

    // The item's length is fixed once; every symbol is centered by NSStatusBarButton.
    func displaySymbol(_ name: String, value: Double = 1, animated: Bool = true) {
        let renderedValue = name.hasPrefix("speaker.wave.") ? value : 1
        let image = NSImage(systemSymbolName: name, variableValue: renderedValue, accessibilityDescription: nil)
        image?.isTemplate = true
        setStatusImage(image, key: "symbol:\(name):\(renderedValue)", symbolName: name, allowTransition: animated)
    }

    private func setStatusImage(_ image: NSImage?, key: String, symbolName: String? = nil, allowTransition: Bool = true) {
        guard let image, displayedIconKey != key else { return }
        let isSymbol = symbolName != nil
        let sameShape = isSymbol ? displayedSymbolName == symbolName : displayedIconKey?.hasPrefix("soniclet:") == true
        let animate = allowTransition && !sameShape && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let wasSymbol = displayedIconKey?.hasPrefix("symbol:") == true
        iconView.removeAllSymbolEffects(animated: false)
        if animate && isSymbol && wasSymbol {
            // Public SF Symbols transition: outgoing layers shrink, incoming layers grow.
            if #available(macOS 15.0, *) {
                // Related symbols (including mute slashes) use Apple's Magic Replace.
                iconView.setSymbolImage(image, contentTransition: .replace.magic(fallback: .replace.downUp.byLayer))
            } else {
                iconView.setSymbolImage(image, contentTransition: .replace.downUp.byLayer)
            }
        } else {
            iconView.image = image
            if animate && isSymbol {
                iconView.addSymbolEffect(.appear)
            } else if animate && displayedIconKey != nil {
                // Raster/template app artwork has no SF Symbol animation layers.
                iconView.wantsLayer = true
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.18
                iconView.layer?.add(fade, forKey: "artworkTransition")
                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 0.75
                scale.toValue = 1
                scale.duration = 0.18
                scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                iconView.layer?.add(scale, forKey: "artworkScale")
            }
        }
        displayedIconKey = key
        displayedSymbolName = symbolName
    }

    func makeDeviceMenu() -> NSMenu {
        let menu = baseMenu()
        menu.minimumWidth = 304
        let heading = NSMenuItem.sectionHeader(title: "Soniclet")
        heading.tag = 900
        heading.view = hosted(Text("Soniclet").font(.headline).frame(width: 280, alignment: .leading)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4))
        menu.addItem(heading)
        let volume = NSMenuItem()
        volume.view = hosted(VolumeMenuContent(model: model).environment(\.controlActiveState, .active))
        menu.addItem(volume)
        menu.addItem(.separator())
        for direction in AudioDirection.allCases {
            menu.addItem(NSMenuItem.sectionHeader(title: direction.title))
            let devices = model.visibleDevices(direction)
            if devices.isEmpty {
                let empty = NSMenuItem(title: L10n.text(direction == .output ? "No output devices to show" : "No input devices to show"), action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
            for device in devices {
                let item = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device.key
                configureDevice(item, device: device)
                menu.addItem(item)
            }
            if let hidden = model.hiddenCurrentDevice(direction) {
                let current = NSMenuItem(title: L10n.format("Current: %@", hidden.name), action: nil, keyEquivalent: "")
                current.isEnabled = false
                current.toolTip = L10n.text("The current device is hidden in settings")
                menu.addItem(current)
            }
            if direction == .output && !model.outputIsAirPlay {
                let hint = NSMenuItem()
                hint.tag = 110
                hint.view = hosted(AirPlayMenuHint { [weak self] in self?.showSystemSoundSettings() })
                menu.addItem(hint)
            }
            menu.addItem(.separator())
        }
        let error = NSMenuItem()
        error.tag = 111
        error.view = hosted(AudioErrorMenuContent(model: model))
        error.isHidden = model.errorMessage == nil
        menu.addItem(error)
        menu.addItem(NSMenuItem.sectionHeader(title: L10n.text("System Settings")))
        menu.addItem(command(L10n.text("Sound Settings…"), #selector(showSystemSoundSettings)))
        if !model.bluetoothOutputs.isEmpty {
            let item = command(SystemSettingsLinks.headphoneTitle(accessory: model.appleHeadphones), #selector(showHeadphoneSettings))
            item.tag = 107
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(command(L10n.text("Soniclet Settings…"), #selector(showSettings)))
        let update = command(updates.menuTitle, #selector(checkForUpdates))
        update.tag = 104
        update.isEnabled = updates.actionIsEnabled
        menu.addItem(update)
        let quit = NSMenuItem(title: L10n.text("Quit Soniclet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        quit.target = NSApplication.shared
        menu.addItem(quit)
        return menu
    }

    private func command(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func hosted<Content: View>(_ content: Content) -> NSView {
        let view = NSHostingView(rootView: content)
        view.sizingOptions = [.intrinsicContentSize]
        view.setFrameSize(view.fittingSize)
        return view
    }

    private func configureDevice(_ item: NSMenuItem, device: AudioDevice) {
        let pending = model.pendingSelection == device.key
        item.title = device.name
        item.state = .off
        item.isEnabled = !pending
        item.setAccessibilityValue(L10n.text(pending ? "Switching" : model.selected(device) ? "Selected" : "Not selected"))
        // Only a disabled pending row needs a view; every selectable row is native.
        if pending {
            if item.view == nil { item.view = hosted(PendingDeviceMenuRow(name: device.name)) }
        } else { item.view = nil }
        item.image = DeviceMenuIcon.image(symbol: model.symbol(for: device), selected: model.selected(device))
        if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
        item.badge = nil
        item.toolTip = nil
        if device.key.direction == .output, let battery = model.accessory(for: device)?.batteryPercent {
            let percent = (Double(battery) / 100).formatted(.percent.precision(.fractionLength(0)))
            item.badge = NSMenuItemBadge(string: percent)
            item.toolTip = L10n.format("Battery: %@", percent)
        }

    }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? DeviceKey,
              let device = model.devices.first(where: { $0.key == key }) else { return }
        model.select(device)
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
        let quit = NSMenuItem(title: L10n.text("Quit Soniclet"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
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
        model.refresh()
        replaceContents(of: menu, with: context ? makeContextMenu() : makeDeviceMenu())
    }

    private func replaceContents(of menu: NSMenu, with content: NSMenu) {
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

    @objc func showSystemSoundSettings() {
        dismissMenu()
        DispatchQueue.main.async { SystemSettingsLinks.openSound() }
    }

    @objc func showHeadphoneSettings() {
        dismissMenu()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            SystemSettingsLinks.openHeadphones(accessory: self.model.appleHeadphones)
        }
    }

    @objc func checkForUpdates() {
        dismissMenu()
        DispatchQueue.main.async { [weak self] in self?.updates.performUserAction() }
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false; forcedContext = nil }
}
