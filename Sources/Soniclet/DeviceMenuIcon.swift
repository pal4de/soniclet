import AppKit

@MainActor
enum DeviceMenuIcon {
    static func image(symbol: String, selected: Bool) -> NSImage? {
        let tint = selected ? NSColor.white : NSColor.labelColor.withAlphaComponent(0.8)
        guard let colored = glyph(symbol: symbol, color: tint, pointSize: 13) else { return nil }
        return NSImage(size: NSSize(width: 26, height: 26), flipped: false) { bounds in
            (selected ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.14)).setFill()
            NSBezierPath(ovalIn: bounds).fill()
            let size = colored.size
            colored.draw(in: NSRect(x: (26 - size.width) / 2, y: (26 - size.height) / 2,
                                    width: size.width, height: size.height))
            return true
        }
    }
    static func glyph(symbol: String, color: NSColor, pointSize: CGFloat) -> NSImage? {
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(.preferringMonochrome())
        let source = glyph.withSymbolConfiguration(configuration) ?? glyph
        return NSImage(size: source.size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            source.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceIn)
            context.endTransparencyLayer()
            context.restoreGState()
            return true
        }
    }

}
