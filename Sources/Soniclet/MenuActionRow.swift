import AppKit

/// One independently tracked menu row. NSMenu still owns the menu and its run loop.
@MainActor
final class MenuActionRow: NSView {
    weak var item: NSMenuItem?
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let batteryLabel = NSTextField(labelWithString: "")
    private let batteryIcon = NSImageView()
    private let progress = NSProgressIndicator()
    private var tracking: NSTrackingArea?
    private var highlighted = false
    private var pointerInside = false
    var displayedIcon: NSImage? { icon.image }
    private var deviceRow = false
    private var hasBattery = false

    init(item: NSMenuItem, device: Bool = false) {
        self.item = item
        deviceRow = device
        super.init(frame: NSRect(x: 0, y: 0, width: 304, height: device ? 32 : 25))
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        batteryLabel.font = .systemFont(ofSize: 11, weight: .medium)
        batteryLabel.textColor = .secondaryLabelColor
        batteryIcon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        batteryIcon.imageScaling = .scaleProportionallyDown
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        for view in [icon, titleLabel, batteryLabel, batteryIcon, progress] {
            view.setAccessibilityElement(false)
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        configure(title: item.title)
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: 304, height: deviceRow ? 32 : 25) }

    func configure(title: String, symbol: String? = nil, selected: Bool = false,
                   pending: Bool = false, battery: Int? = nil) {
        titleLabel.stringValue = title
        titleLabel.textColor = item?.isEnabled == false ? .secondaryLabelColor : .labelColor
        toolTip = title
        icon.image = symbol.flatMap { DeviceMenuIcon.image(symbol: $0, selected: selected) }
        icon.isHidden = !deviceRow || pending
        if pending { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        hasBattery = battery != nil
        if let battery {
            let percent = (Double(battery) / 100).formatted(.percent.precision(.fractionLength(0)))
            batteryLabel.stringValue = percent
            batteryIcon.image = NSImage(systemSymbolName: "battery.\(min(100, ((battery + 12) / 25) * 25))percent", accessibilityDescription: nil)
            batteryIcon.image?.isTemplate = true
            setAccessibilityHelp(L10n.format("Battery: %@", percent))
        } else { setAccessibilityHelp(nil) }
        batteryLabel.isHidden = !hasBattery
        batteryIcon.isHidden = !hasBattery
        setAccessibilityLabel(title)
        setAccessibilityValue(deviceRow ? L10n.text(pending ? "Switching" : selected ? "Selected" : "Not selected") : nil)
        setAccessibilityEnabled(item?.isEnabled ?? false)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let left: CGFloat = deviceRow ? 47 : 12
        let middle = bounds.midY
        icon.frame = NSRect(x: 12, y: middle - 13, width: 26, height: 26)
        progress.frame = NSRect(x: 17, y: middle - 8, width: 16, height: 16)
        batteryIcon.frame = NSRect(x: bounds.width - 32, y: middle - 7, width: 20, height: 14)
        let batteryWidth = batteryLabel.intrinsicContentSize.width
        batteryLabel.frame = NSRect(x: batteryIcon.frame.minX - 4 - batteryWidth, y: middle - 8, width: batteryWidth, height: 16)
        let right = hasBattery ? batteryLabel.frame.minX - 8 : bounds.width - 12
        titleLabel.frame = NSRect(x: left, y: middle - 9, width: max(0, right - left), height: 18)
        let rtl = userInterfaceLayoutDirection == .rightToLeft
        titleLabel.alignment = rtl ? .right : .left
        if rtl {
            for view in [icon, titleLabel, batteryLabel, batteryIcon, progress] {
                var frame = view.frame
                frame.origin.x = bounds.width - frame.maxX
                view.frame = frame
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        if (highlighted || pointerInside) && item?.isEnabled == true {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 6, yRadius: 6).fill()
        }
    }
    func setHighlighted(_ value: Bool) {
        highlighted = value
        if NSApp.currentEvent?.type == .keyDown { pointerInside = false }
        needsDisplay = true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { pointerInside = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { pointerInside = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { pointerInside = true; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { pointerInside = bounds.contains(convert(event.locationInWindow, from: nil)); needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        activate()
    }
    override func accessibilityPerformPress() -> Bool { activate() }

    @discardableResult
    private func activate() -> Bool {
        guard let item, item.isEnabled, let menu = item.menu else { return false }
        let index = menu.index(of: item)
        guard index >= 0 else { return false }
        menu.cancelTrackingWithoutAnimation()
        menu.performActionForItem(at: index)
        return true
    }
}
