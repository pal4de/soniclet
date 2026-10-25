import AppKit

@main
struct StatusMarkTests {
    static func require(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    @MainActor
    static func main() {
        let bundle = Bundle(path: CommandLine.arguments[1])!
        let levels: [(Float, Int)] = [(0, 0), (0.01, 1), (1.0 / 3.0, 1), (0.5, 2), (2.0 / 3.0, 2), (1, 3)]
        for (volume, expected) in levels {
            require(StatusMark.level(volume: volume, muted: false) == expected, "Volume level \(volume)")
        }
        require(StatusMark.level(volume: 1, muted: true) == 0, "Muted means all waveform bars dimmed")
        require(StatusMark.level(volume: nil, muted: false) == 3, "Unknown hardware volume remains visible")
        for level in 0...3 {
            guard let image = StatusMark.makeImage(level: level, bundle: bundle) else { fatalError("Missing status mark") }
            require(image.isTemplate && image.size == NSSize(width: 18, height: 18), "Fixed-size native template")
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: NSRect(x: 0, y: 0, width: 180, height: 180))
            NSGraphicsContext.restoreGraphicsState()
            for (index, x) in [73, 90, 107].enumerated() {
                let alpha = bitmap.colorAt(x: x, y: 90)!.alphaComponent
                let expected: CGFloat = index < level ? 1 : 0.3
                require(abs(alpha - expected) < 0.08, "Waveform opacity at level \(level), bar \(index): \(alpha)")
            }
            require(bitmap.colorAt(x: 26, y: 90)!.alphaComponent > 0.95, "Routing arrows stay opaque")
        }
        print("PASS: menu-bar template size, stepped waveform opacity, muted state, and opaque routing arrows")
    }
}
