import SwiftUI
import UniformTypeIdentifiers

struct SoundMenuContent: View {
    @ObservedObject var model: AudioModel
    @ObservedObject var updates: UpdateChecker
    var updateAction: () -> Void
    var settingsAction: () -> Void
    var dismissPanel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Soniclet").font(.headline)
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            volumeControl.padding(.horizontal, 12).padding(.bottom, 8)
            Divider().padding(.horizontal, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    deviceSection(.output)
                    Divider().padding(.horizontal, 12).padding(.top, 5)
                    deviceSection(.input)
                }.padding(.bottom, 6)
            }.scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 400)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel(L10n.text("Close error"))
                }.padding(12)
            }
            Divider().padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.text("System Settings")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 3)
                Button(action: openSystemSettings) { footerLabel("Sound Settings…") }
                if !model.bluetoothOutputs.isEmpty {
                    Button(action: openHeadphoneSettings) {
                        Text(SystemSettingsLinks.headphoneTitle(accessory: model.appleHeadphones)).font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                }
                Divider().padding(.horizontal, 6).padding(.vertical, 3)
                Button(action: settingsAction) { footerLabel("Soniclet Settings…") }
                    .keyboardShortcut(",", modifiers: .command)
                Button(action: updateAction) {
                    Text(updates.menuTitle).font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .contentShape(Rectangle())
                }.disabled(!updates.actionIsEnabled)
                Button { NSApplication.shared.terminate(nil) } label: { footerLabel("Quit Soniclet") }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(MenuRowButtonStyle())
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .frame(width: 304)
        .onAppear { model.refresh() }
    }

    private func footerLabel(_ key: String) -> some View {
        Text(L10n.text(key)).font(.callout)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .contentShape(Rectangle())
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Button { model.stepVolume(up: false) } label: {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(MenuRowButtonStyle())
            .disabled(!model.outputVolume.canAdjust)
            .accessibilityLabel(L10n.text("Decrease volume"))
            .help(L10n.text("Decrease volume"))
            Slider(value: Binding(get: { Double(model.outputVolume.muted ? 0 : model.outputVolume.value) },
                                  set: { model.changeVolume(Float($0)) }), in: 0...1)
                .controlSize(.large)
                .tint(Color(nsColor: .controlAccentColor))
                .disabled(!model.outputVolume.canAdjust)
                .accessibilityLabel(L10n.text("Output volume"))
                .accessibilityValue(model.outputVolume.canAdjust
                    ? Double(model.outputVolume.muted ? 0 : model.outputVolume.value).formatted(.percent.precision(.fractionLength(0)))
                    : L10n.text("Volume cannot be adjusted for this device"))
                .help(model.outputVolume.canAdjust ? L10n.format("Volume for %@", model.outputName) : L10n.text("Adjust the volume on the device"))
            Button { model.stepVolume(up: true) } label: {
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(MenuRowButtonStyle())
            .disabled(!model.outputVolume.canAdjust)
            .accessibilityLabel(L10n.text("Increase volume"))
            .help(L10n.text("Increase volume"))
        }
        .font(.system(size: 15))
        .frame(height: 24)
    }
    private func openHeadphoneSettings() {
        dismissPanel()
        SystemSettingsLinks.openHeadphones(accessory: model.appleHeadphones)
    }

    private func openSystemSettings() {
        dismissPanel()
        SystemSettingsLinks.openSound()
    }
    private func deviceSection(_ direction: AudioDirection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(direction.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 3)
            let devices = model.visibleDevices(direction)
            if devices.isEmpty {
                Text(L10n.text(direction == .output ? "No output devices to show" : "No input devices to show"))
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
            }
            ForEach(devices) { device in
                DeviceRow(device: device, selected: model.selected(device),
                          pending: model.pendingSelection == device.key,
                          batteryPercent: direction == .output ? model.accessory(for: device)?.batteryPercent : nil) { model.select(device) }
                    .padding(.horizontal, 6)
            }
            if let hidden = model.hiddenCurrentDevice(direction) {
                Text(L10n.format("Current: %@", hidden.name))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.top, 5)
                    .help(L10n.text("The current device is hidden in settings"))
            }
            if direction == .output {
                Text(LocalizedStringKey(L10n.text("Connect AirPlay devices in System Sound Settings first.")))
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.absoluteString == "soniclet://sound-settings" else { return .discarded }
                        openSystemSettings()
                        return .handled
                    })
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.top, 5)
            }
        }
    }
}

private struct DeviceRow: View {
    let device: AudioDevice
    let selected: Bool
    let pending: Bool
    let batteryPercent: Int?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Group {
                    if pending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: device.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(selected ? Color.white : Color.secondary)
                    }
                }
                .frame(width: 26, height: 26)
                .background(!pending && selected ? Color.accentColor : Color.primary.opacity(0.07), in: Circle())
                Text(device.name).font(.body).lineLimit(1)
                Spacer(minLength: 4)
                if let batteryPercent {
                    let percent = (Double(batteryPercent) / 100).formatted(.percent.precision(.fractionLength(0)))
                    HStack(spacing: 3) {
                        Text(percent).monospacedDigit()
                        Image(systemName: "battery.\(min(100, ((batteryPercent + 12) / 25) * 25))percent")
                    }.font(.caption).foregroundStyle(.secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.format("Battery: %@", percent))
                        .help(L10n.format("Battery: %@", percent))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .help(device.name)
        .accessibilityLabel(device.name)
        .accessibilityValue(L10n.text(pending ? "Switching" : selected ? "Selected" : "Not selected"))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

struct DeviceSettingsView: View {
    @ObservedObject var model: AudioModel
    @StateObject private var loginItem = LoginItemModel()
    @AppStorage(MenuBarIconStyle.preferenceKey) private var menuBarIconStyle = MenuBarIconStyle.system
    var body: some View {
        Form {
            Section(L10n.text("General")) {
                Picker(L10n.text("Menu bar icon"), selection: $menuBarIconStyle) {
                    Label {
                        Text(L10n.text("System icon"))
                    } icon: {
                        Image(systemName: "speaker.wave.3.fill", variableValue: 0.5)
                    }.labelStyle(.titleAndIcon).tag(MenuBarIconStyle.system)
                    Label {
                        Text("Soniclet")
                    } icon: {
                        Image(nsImage: StatusMark.image(volume: 0.5, muted: false) ?? NSImage())
                            .renderingMode(.template)
                    }.labelStyle(.titleAndIcon).tag(MenuBarIconStyle.soniclet)
                }.pickerStyle(.menu)
                Toggle(L10n.text("Launch at login"), isOn: Binding(
                    get: { loginItem.isRequested }, set: { loginItem.setEnabled($0) }
                )).toggleStyle(.checkbox)
                if loginItem.needsApproval {
                    Text(L10n.text("Approval is required in System Settings.")).foregroundStyle(.secondary)
                    Button(L10n.text("Open Login Items Settings…")) { loginItem.openSystemSettings() }
                }
                if let error = loginItem.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
            }
            ForEach(AudioDirection.allCases, id: \.self) { direction in
                Section {
                    let devices = model.savedDevices(direction)
                    if devices.isEmpty {
                        Text(L10n.text(direction == .output ? "No output devices" : "No input devices")).foregroundStyle(.secondary)
                    }
                    ForEach(devices) { preference in
                        DevicePreferenceRow(model: model, preference: preference)
                    }
                } header: {
                    Text(direction.title)
                } footer: {
                    Text([
                        L10n.text("Choose which devices appear in the menu."),
                        L10n.text("Drag devices to change their order in the menu."),
                        L10n.text("Hiding a device does not change the current input, output, or settings in other apps.")
                    ].joined(separator: " "))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 580)
        .onAppear { model.refresh(); loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
}

/// NSMenu's custom content contains ordinary SwiftUI controls.
/// Use SwiftUI's hover tracking and semantic system shading for a shared row style.
private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.modifier(MenuRowHighlight(isPressed: configuration.isPressed))
    }
}

private struct MenuRowHighlight: ViewModifier {
    let isPressed: Bool
    // Disambiguate the State property wrapper from the SDK's State macro.
    private typealias HoverFlag = State<Bool>
    @HoverFlag private var hovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isPressed ? .tertiary : .quaternary)
                    .opacity(hovered || isPressed ? 1 : 0)
            }
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
    }
}


private struct DeviceDragItem: Codable, Transferable {
    let key: DeviceKey
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "io.github.pal4de.soniclet.device", conformingTo: .data))
    }
}

private struct DevicePreferenceRow: View {
    @ObservedObject var model: AudioModel
    let preference: DevicePreference
    private typealias RowHeight = State<CGFloat>
    @RowHeight private var rowHeight: CGFloat = 28
    private var direction: AudioDirection { preference.key.direction }
    private var index: Int { model.savedDevices(direction).firstIndex { $0.key == preference.key } ?? 0 }

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: {
                model.preferences.first { $0.key == preference.key }?.isVisible ?? true
            }, set: { model.setVisible($0, key: preference.key) })) {
                HStack(spacing: 8) {
                    Image(systemName: preference.symbol).foregroundStyle(.secondary).frame(width: 20)
                    Text(preference.name)
                    Spacer(minLength: 4)
                    if !model.isConnected(preference.key) {
                        Text(L10n.text("Not connected")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(L10n.format("Show %@ (%@)", preference.name, direction.title))
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 24)
                .contentShape(Rectangle())
                .help(L10n.text("Drag devices to change their order in the menu."))
                .accessibilityLabel(L10n.text("Drag devices to change their order in the menu."))
                .draggable(DeviceDragItem(key: preference.key))
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .dropDestination(for: DeviceDragItem.self) { items, point in
            guard items.count == 1 else { return false }
            return model.moveDevice(items[0].key, relativeTo: preference.key, after: point.y > rowHeight / 2)
        }
        .contextMenu {
            Button(L10n.text("Move Up"), systemImage: "chevron.up") {
                model.moveDevices(direction, from: IndexSet(integer: index), to: index - 1)
            }.disabled(index == 0)
            Button(L10n.text("Move Down"), systemImage: "chevron.down") {
                model.moveDevices(direction, from: IndexSet(integer: index), to: index + 2)
            }.disabled(index >= model.savedDevices(direction).count - 1)
        }
        .accessibilityAction(named: Text(L10n.text("Move Up"))) {
            model.moveDevices(direction, from: IndexSet(integer: index), to: index - 1)
        }
        .accessibilityAction(named: Text(L10n.text("Move Down"))) {
            model.moveDevices(direction, from: IndexSet(integer: index), to: index + 2)
        }
    }
}
