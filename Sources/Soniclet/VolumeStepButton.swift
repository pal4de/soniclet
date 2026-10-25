import AppKit
import SwiftUI

/// AppKit owns press highlighting, cancellation and held-button repetition.
struct VolumeStepButton: NSViewRepresentable {
    let up: Bool
    let enabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(), target: context.coordinator, action: #selector(Coordinator.step))
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.showsBorderOnlyWhileMouseInside = false
        button.isContinuous = true
        button.setPeriodicDelay(0.35, interval: 0.08)
        (button.cell as? NSButtonCell)?.highlightsBy = .contentsCellMask
        updateNSView(button, context: context)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        let symbol = up ? "speaker.wave.3.fill" : "speaker.fill"
        button.image = DeviceMenuIcon.glyph(symbol: symbol, color: .secondaryLabelColor, pointSize: 15)
        button.alternateImage = DeviceMenuIcon.glyph(symbol: symbol, color: .labelColor, pointSize: 15)
        button.imageScaling = .scaleProportionallyDown
        button.isEnabled = enabled
        button.setAccessibilityLabel(L10n.text(up ? "Increase volume" : "Decrease volume"))
        button.toolTip = nil
    }
    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func step() { action() }
    }
}
