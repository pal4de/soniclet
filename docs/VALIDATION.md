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
- Developer Program membership and local Developer ID notarization are confirmed; see the exact artifact record below. App Store provisioning, distribution signing, upload and review remain outstanding. Local Sandbox observations are documented in SANDBOX.md.

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

## 0.7.6 Developer ID distribution artifact

Verified 2026-10-26 on macOS 27.2. Runtime sources were built from commit `163a1053898ba9074af9e20a002e2e4e6e62b274`; subsequent documentation changes do not change this executable.

- App version/build: **0.7.6 (20)**, direct-download channel, `io.github.pal4de.soniclet`.
- Universal executable: arm64 and x86_64 slices verified independently; Intel hardware operation remains untested.
- Developer ID Application signature verified with Hardened Runtime and Apple's secure timestamp. No certificate private key was exported.
- Notarization submission: `b4783bce-25ba-4138-a8b6-a8d58a459e20`, **Accepted**; Apple's submission log reported no issues.
- Ticket stapling and validation succeeded. After extracting the final ZIP into a fresh temporary directory, strict deep signature verification, ticket validation and Gatekeeper assessment all passed (`source=Notarized Developer ID`). The app was not launched or installed for this packaging check.
- Archive: `Soniclet-universal.zip`.
- SHA-256: `2c99a9f1a2cdbfd8ee8fdcfc71e8ba23d59bd78dc03f3d9f1ca36d3a3a4a79da`.
- The full local automated test suite passed before submission. The application commit's GitHub CI also passed.
- At this verification, the independent tap's draft cask was regenerated from this exact notarized ZIP; the later 0.7.7 record supersedes its current pointer. Its online URL/install/upgrade check is pending publication of the matching reviewed Release; neither PR has been merged and no Release has been published.

Do not substitute a newly generated ad-hoc CI ZIP under this checksum or call another archive notarized based on this record. Repackaging requires a fresh SHA-256 and cask update.

## 0.7.7 settings tabs

Settings is split into native General, Output and Input tabs using SwiftUI's current Tab API inside the Settings scene. macOS 14 retains the standard tabItem compatibility path. Each tab has a grouped Form; device order, visibility, automatic-selection policy and preference keys are unchanged. The OS owns the toolbar/pane titles and tab selection.

The actual accessory-app GUI smoke test selects all three native panes, captures each, restores General and verifies settings reopening/window reuse along with existing menu checks. It runs with the explicit background-focus allowance; it does not change device routing, volume or login registration. Standard ordering remains in each direction's reorderContainer. Old-OS hardware validation remains omitted.

The 0.7.7 (21) direct universal distribution artifact was built from runtime source commit `327195ff8b65f0dec8b665dfe8415d5bd8f35376`, Developer ID signed and accepted by Apple under submission `5288540f-43f0-4674-aa77-8d9ea270bfb2`. Ticket stapling, strict signature verification, both CPU slices and Gatekeeper assessment passed again after extracting the final ZIP. The installed app was updated to this version.

Local versioned archive: `Soniclet-0.7.7-universal.zip`; release asset name remains `Soniclet-universal.zip` with identical bytes. SHA-256: `cb0c2e10b7408bd353a271e7be69be8321e21cbd78550dbdb766132c6cad3635`. The tap's draft cask matches this artifact. Both direct and enforced-Sandbox GUI smoke tests passed the tab selection and reopening checks. Release publication, tap installation/upgrade and physical drag verification remain separate.

## 0.7.8 direction-settings sections

Automatic selection now has its own native Form Section and uses SwiftUI's switch style. Device visibility/order remain in a separate Section; the existing bindings and reorderContainer are retained. No custom control, setting migration or routing-policy change was introduced.

Universal Developer ID artifact built from runtime source commit `e66281b`: version 0.7.8 (22), notarization submission `f4984dae-751b-4e6e-a2d2-a43f0eb20e2e`, **Accepted**. Ticket validation, strict signature, both CPU slices and Gatekeeper passed after extracting the final ZIP. Installed locally; normal and enforced-Sandbox GUI smoke tests passed in explicit background-focus mode. Native tab navigation, settings reopening and menu checks remain passing.

Archive: `Soniclet-0.7.8-universal.zip` (same bytes as the release filename `Soniclet-universal.zip`). SHA-256: `85818d2d666d93494ac082d36b5b03f0905991e3a229ac4db1c8accf5477f019`. The draft tap cask matches this version; publication and online install/upgrade checks remain pending.

## 0.7.9 automatic-selection help

The automatic-selection Section footer now explains connection-driven switching and always shows priority/hidden-device behavior next to the switch, including when disabled. The device-list footer retains visibility/reordering help, with the unchanged-route explanation only while automatic selection is disabled. Added the explanation in all 34 languages; localization validation covers 66 strings per language. Existing native Form footer styles are used, with no routing or preference changes. Direct and enforced-Sandbox settings/menu smoke tests passed in background-focus-allowed mode.

Runtime source commit `a18dfe9`, version 0.7.9 (23), universal Developer ID build. Apple notarization `2dc2383c-5282-4d51-a911-de5c1d7ba1b1`: **Accepted**. Stapling, extracted-ZIP signature/ticket/architecture checks and Gatekeeper passed. Installed locally. Archive `Soniclet-0.7.9-universal.zip` is byte-identical to the staged release filename `Soniclet-universal.zip`; SHA-256 `a1b0400a9b17887fd5044cff243e85352a8668d3f45360afb1ebd8170689da3e`. The draft cask matches this artifact; release publication and online Homebrew installation remain pending.
