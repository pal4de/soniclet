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

## 0.7.1 regression coverage

Pure tests cover reflection beyond one second, a transient target overwritten by another route, stable confirmation, five-second timeout, disconnection and confirmation near the deadline. Policy tests verify that failure and late reflection never invent manual selection, explicit manual targets survive failure, repeated default notifications cannot restart failed writes, and new connection contexts allow reevaluation. Physical Bluetooth negotiation remains a separate observation.

After installing 0.7.1, a live readback showed the configured Bluetooth output retained and the preferred USB input selected. Both automatic-selection switches remained enabled and no manual-mode resume control was present. This verifies the current startup path, not every physical reconnect or Bluetooth negotiation sequence.

## 0.7.2 menu refresh regression

A live readback confirmed the preferred USB input even though an already-open menu retained the former hidden input label. Hidden-current rows now remain native placeholders, with title and visibility recomputed on every menu update. The GUI regression injects stale input/output labels into an open menu and checks they are refreshed without audio writes or replacing native menu tracking.

## 0.7.3 destination preview regression

The native GUI test renders a synthetic AirPods Pro output event without changing audio routing, compares the actual displayed image to the AirPods symbol, applies a following input event and model update, and checks that the output preview remains until restoring the chosen icon after two seconds. Physical connection timing remains separately observable.

Policy regressions also cover a connection where macOS has already selected the preferred route: it reports destination feedback without writing the default again, and does not repeat on unchanged refreshes or manual default-only changes. Combine delivers distinct output/input events in order so an input adjustment cannot replace an unseen output event.

## 0.7.5 settings and menu commands

A native Resume Automatic Selection command appears immediately above Soniclet Settings only for enabled directions with manual overrides, and resumes them together without enabling disabled directions. GUI checks cover command position and live visibility. Settings now observes the same UpdateChecker instance as the status menu, sharing in-flight and available-release state. Offline update fixtures remain the network-contract checks.
