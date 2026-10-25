import AppKit

enum MenuBarIconStyle: String, CaseIterable {
    case system, device, soniclet
    func symbol(device: String, volume: String) -> String { self == .device ? device : volume }
    static let preferenceKey = "menuBarIconStyle"
    static func current(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .system
    }
}

/// A template image lets AppKit choose the correct light/dark menu-bar tint.
@MainActor
enum StatusMark {
    private static let images = (0...3).map { makeImage(level: $0) }

    static func level(volume: Float?, muted: Bool) -> Int {
        if muted { return 0 }
        guard let volume, volume.isFinite else { return 3 }
        if volume <= 0 { return 0 }
        if volume <= 1.0 / 3.0 { return 1 }
        if volume <= 2.0 / 3.0 { return 2 }
        return 3
    }

    static func image(volume: Float?, muted: Bool) -> NSImage? {
        images[level(volume: volume, muted: muted)]
    }

    static func makeImage(level: Int, bundle: Bundle = .main) -> NSImage? {
        guard let url = bundle.url(forResource: "StatusMark", withExtension: "svg"),
              var svg = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for index in 1...3 {
            let opacity = index <= level ? "1" : "0.3"
            svg = svg.replacingOccurrences(of: "<rect id=\"level-\(index)\"",
                                          with: "<rect opacity=\"\(opacity)\" id=\"level-\(index)\"")
        }
        guard let source = NSImage(data: Data(svg.utf8)) else { return nil }
        let result = NSImage(size: NSSize(width: 19, height: 19), flipped: false) { rect in
            // Crop only the artwork's square silhouette, excluding app-icon padding.
            source.draw(in: rect, from: NSRect(x: 172, y: 172, width: 680, height: 680),
                        operation: .sourceOver, fraction: 1)
            return true
        }
        result.isTemplate = true
        return result
    }
}
