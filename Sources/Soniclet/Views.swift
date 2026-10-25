import SwiftUI

struct SoundPopover: View {
    @ObservedObject var model: AudioModel
    var settingsAction: (() -> Void)? = nil
    var dismissPanel: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("Sound")).font(.headline)
                .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 8)
            volumeControl.padding(.horizontal, 14).padding(.bottom, 10)
            Divider().padding(.horizontal, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    deviceSection(.output)
                    Divider().padding(.horizontal, 12).padding(.top, 7)
                    deviceSection(.input)
                }.padding(.bottom, 8)
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
                Button(action: openSystemSettings) { footerLabel("System Sound Settings…") }
                Button {
                    dismiss()
                    if let settingsAction { settingsAction() }
                    else { SettingsPresentation.open(openSettings) }
                } label: { footerLabel("Soniclet Settings…") }
                    .keyboardShortcut(",", modifiers: .command)
                Divider().padding(.horizontal, 6).padding(.vertical, 4)
                Button { NSApplication.shared.terminate(nil) } label: { footerLabel("Quit Soniclet") }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(MenuRowButtonStyle())
            .padding(.horizontal, 6).padding(.vertical, 5)
        }
        .frame(width: 320)
        .onAppear { model.refresh() }
    }

    private func footerLabel(_ key: String) -> some View {
        Text(L10n.text(key)).font(.callout)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(Rectangle())
    }

    private var volumeControl: some View {
        HStack(spacing: 8) {
            Button { model.stepVolume(up: false) } label: {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(MenuRowButtonStyle())
            .disabled(!model.outputVolume.canAdjust)
            .accessibilityLabel(L10n.text("Decrease volume"))
            .help(L10n.text("Decrease volume"))
            Slider(value: Binding(get: { Double(model.outputVolume.muted ? 0 : model.outputVolume.value) },
                                  set: { model.changeVolume(Float($0)) }), in: 0...1)
                .controlSize(.large)
                .disabled(!model.outputVolume.canAdjust)
                .accessibilityLabel(L10n.text("Output volume"))
                .accessibilityValue(model.outputVolume.canAdjust
                    ? Double(model.outputVolume.muted ? 0 : model.outputVolume.value).formatted(.percent.precision(.fractionLength(0)))
                    : L10n.text("Volume cannot be adjusted for this device"))
                .help(model.outputVolume.canAdjust ? L10n.format("Volume for %@", model.outputName) : L10n.text("Adjust the volume on the device"))
            Button { model.stepVolume(up: true) } label: {
                Image(systemName: model.outputSymbol).foregroundStyle(.secondary)
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(MenuRowButtonStyle())
            .disabled(!model.outputVolume.canAdjust)
            .accessibilityLabel(L10n.text("Increase volume"))
            .help(L10n.text("Increase volume"))
        }
        .font(.system(size: 15))
        .frame(height: 28)
    }
    private func openSystemSettings() {
        dismissPanel?()
        dismiss()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        if !NSWorkspace.shared.open(url) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
    private func deviceSection(_ direction: AudioDirection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(direction.title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 3)
            let devices = model.visibleDevices(direction)
            if devices.isEmpty {
                Text(L10n.text(direction == .output ? "No output devices to show" : "No input devices to show"))
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 7)
            }
            ForEach(devices) { device in
                DeviceRow(device: device, selected: model.selected(device),
                          pending: model.pendingSelection == device.key) { model.select(device) }
                    .padding(.horizontal, 6)
            }
            if let hidden = model.hiddenCurrentDevice(direction) {
                Text(L10n.format("Current: %@", hidden.name))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.top, 5)
                    .help(L10n.text("The current device is hidden in settings"))
            }
            if direction == .output {
                Text(L10n.text("Connect AirPlay devices in System Sound Settings first."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.top, 5)
            }
        }
    }
}

private struct DeviceRow: View {
    let device: AudioDevice
    let selected: Bool
    let pending: Bool
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
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
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
    var body: some View {
        Form {
            Section {
                Text(L10n.text("Choose which devices appear in the menu."))
                Text(L10n.text("Hiding a device does not change the current input, output, or settings in other apps."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section(L10n.text("General")) {
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
                Section(direction.title) {
                    let devices = model.savedDevices(direction)
                    if devices.isEmpty {
                        Text(L10n.text(direction == .output ? "No output devices" : "No input devices")).foregroundStyle(.secondary)
                    }
                    ForEach(devices) { preference in
                        Toggle(isOn: Binding(get: {
                            model.preferences.first { $0.key == preference.key }?.isVisible ?? true
                        }, set: { model.setVisible($0, key: preference.key) })) {
                            HStack(spacing: 8) {
                                Image(systemName: preference.symbol).foregroundStyle(.secondary).frame(width: 20)
                                Text(preference.name)
                                if !model.isConnected(preference.key) {
                                    Spacer()
                                    Text(L10n.text("Not connected")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(L10n.format("Show %@ (%@)", preference.name, direction.title))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 580)
        .onAppear { model.refresh(); loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
}

/// MenuBarExtra's window style contains ordinary views, not NSMenuItems.
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

@MainActor
enum SettingsPresentation {
    static func open(_ action: OpenSettingsAction) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        action()
    }
}
