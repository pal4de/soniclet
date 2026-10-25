# Development guidance

## Product
Keep this a small, native macOS audio-device switcher. Prefer public Apple APIs and system behavior over custom infrastructure. Do not add drivers, private frameworks, audio interception, per-app processing, or dependencies without a concrete requirement.

## Implementation
- Use AppKit for status items, NSMenu tracking/placement, and window lifecycle; SwiftUI for view content and native settings scenes. Retain the small availability fallback for older macOS.
- Keep the device menu permanently assigned to NSStatusItem.menu. Let AppKit handle mouse-down tracking, outside clicks, Escape, keyboard navigation, positioning, and square status-item sizing. Host custom controls with NSMenuItem.view; use menuNeedsUpdate to prepare content rather than synthetic click routing or event monitors.
- Prefer standard controls, semantic styles, SF Symbols, accessibility, keyboard behavior, and automatic locale/direction handling. Do not imitate inaccessible private Control Center UI.
- Let Core Audio own device/default/volume state and ServiceManagement own login-item state. Observe and read back system state; do not maintain competing sources of truth.
- Persist only user preferences. Identify devices by UID and direction, never transient AudioObjectID. Preserve stored settings compatibility. Do not retain disconnected AirPlay session endpoints.
- Keep app identity stable after publication. Renaming the app must not silently discard preferences or duplicate login items.
- Keep errors actionable. Never silently reroute audio as a fallback. Hiding devices only affects this app's list.
- Use Foundation networking for release checks. Do not download or execute updates. Validate release links before opening them.
- Localize every user-facing string in all bundled languages. Preserve formatting placeholders. Treat translations as open to native-speaker review.

## Validation
Run `./build.sh` and `./test.sh`. For changes to settings, status-item routing, menus, or menu layout, also run `./test-settings.sh` in a logged-in graphical macOS session. A normal SwiftUI window does not reproduce accessory-app settings behavior. Do not run GUI tests concurrently with other UI automation.

Add tests for meaningful contracts, migrations, and failure cases. Avoid tests that merely repeat implementation. Hardware switching and AirPlay require manual verification; do not change someone's audio routing, volume, or login setting merely to run a test.

## Distribution
Never commit build artifacts, signing credentials, personal device names, local screenshots, or development caches. Keep CI permissions minimal. Build unsigned/ad-hoc artifacts distinctly from Developer ID signed and notarized releases; do not claim notarization without verifying it. Make release publication an explicit operation.
