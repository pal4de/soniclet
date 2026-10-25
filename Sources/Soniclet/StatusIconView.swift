import AppKit

/// A standard symbol-capable image view; the status button still handles every click.
final class StatusIconView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
