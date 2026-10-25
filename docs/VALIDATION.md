# Validation status

Updated 2026-10-26. User observations and automated checks are separate evidence.

## User-confirmed

- Native menu press-hold-slide-release selects the hovered device correctly.
- Volume feedback is audible. The previous Pop alert was the wrong sound; the replacement uses the installed volume-key sound and still needs listening confirmation.
- Current AirPods icon appears acceptable; no further visual matching is requested.
- The previous settings drag implementation was usable but unsatisfactory: only foreground content lifted, and the insertion position was unclear. It is replaced by the macOS 27 system reordering API; the new physical drag behavior still needs confirmation.

## Deferred or omitted

- VoiceOver: no manual screen-reader audit is required at present; continue using native controls and accessibility labels/actions. This is not a claim of VoiceOver certification.
- Older macOS hardware verification: omitted because no test environment is available. Compatibility branches remain, but are not hardware-verified.
- Sleep/wake: not yet manually checked. Verify that devices, defaults and volume refresh after waking, and that switching still works. The app already refreshes and reinstalls volume observation on NSWorkspace.didWakeNotification.
- Automatic routing: opt-in implementation added, with pure-policy tests. Native GUI checks verify temporary speaker display and restoration after two seconds, without changing the icon preference or audio routing. Physical connection/disconnection and alert interaction still need manual validation.
- Keeping the menu open after device selection: deferred in GitHub issue #2. Keep native menu interactions.
- Developer Program application submitted; membership activation is pending. Actual distribution signing, notarization and App Store sandbox validation remain outstanding.
