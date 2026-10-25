import AppKit

@MainActor
enum DeviceMenuIcon {
    static func image(symbol: String, selected: Bool) -> NSImage? {
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium)) else { return nil }
        // Only the icon is composed; NSMenuItem owns the row, highlight and tracking.
        let tint = selected ? NSColor.white : NSColor.secondaryLabelColor
        let colored = glyph.withSymbolConfiguration(.init(paletteColors: [tint])) ?? glyph
        return NSImage(size: NSSize(width: 26, height: 26), flipped: false) { bounds in
            (selected ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.07)).setFill()
            NSBezierPath(ovalIn: bounds).fill()
            let size = colored.size
            colored.draw(in: NSRect(x: (26 - size.width) / 2, y: (26 - size.height) / 2,
                                    width: size.width, height: size.height))
            return true
        }
    }
}
