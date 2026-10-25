import SwiftUI

struct VolumeMenuContent: View {
    @ObservedObject var model: AudioModel
    private typealias InitialVolume = State<Float?>
    @InitialVolume private var initialVolume: Float?
    var body: some View {
        HStack(spacing: 4) {
            VolumeStepButton(up: false, enabled: model.outputVolume.canAdjust) { model.stepVolume(up: false) }
                .frame(width: 18, height: 24)
            Slider(value: Binding(get: { Double(model.outputVolume.muted ? 0 : model.outputVolume.value) },
                                  set: { model.changeVolume(Float($0)) }), in: 0...1,
                   onEditingChanged: { editing in
                       if editing { initialVolume = model.outputVolume.value }
                       else {
                           if let initialVolume, initialVolume != model.outputVolume.value { model.playVolumeFeedback() }
                           initialVolume = nil
                       }
                   })
                .controlSize(.large)
                .tint(Color(nsColor: .controlAccentColor))
                .disabled(!model.outputVolume.canAdjust)
                .accessibilityLabel(L10n.text("Output volume"))
                .accessibilityValue(model.outputVolume.canAdjust
                    ? Double(model.outputVolume.muted ? 0 : model.outputVolume.value).formatted(.percent.precision(.fractionLength(0)))
                    : L10n.text("Volume cannot be adjusted for this device"))
                .help(model.outputVolume.canAdjust ? L10n.format("Volume for %@", model.outputName) : L10n.text("Adjust the volume on the device"))
            VolumeStepButton(up: true, enabled: model.outputVolume.canAdjust) { model.stepVolume(up: true) }
                // The sound waves make this glyph wider; preserve the same optical gap as the left endpoint.
                .frame(width: 30, height: 24)
        }
        .frame(height: 24)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(width: 304)
    }
}

struct AirPlayMenuHint: View {
    let openSettings: () -> Void
    var body: some View {
        Text(LocalizedStringKey(L10n.text("Select AirPlay devices in System Sound Settings.")))
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 280, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .environment(\.openURL, OpenURLAction { url in
                guard url.absoluteString == "soniclet://sound-settings" else { return .discarded }
                openSettings()
                return .handled
            })
    }
}

struct AudioErrorMenuContent: View {
    @ObservedObject var model: AudioModel
    var body: some View {
        if let message = model.errorMessage {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
                Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).accessibilityLabel(L10n.text("Close error"))
            }.padding(12).frame(width: 304)
        }
    }
}

struct DeviceSettingsView: View {
    @ObservedObject var model: AudioModel
    @ObservedObject var updates: UpdateChecker
    @StateObject private var loginItem = LoginItemModel()
    @AppStorage(MenuBarIconStyle.preferenceKey) private var menuBarIconStyle = MenuBarIconStyle.system
    private var reorderHelp: String {
        if #available(macOS 27, *) { return L10n.text("Drag devices to change their order in the menu.") }
        return "\(L10n.text("Move Up")) / \(L10n.text("Move Down"))"
    }
    var body: some View {
        Form {
            Section(L10n.text("General")) {
                Picker(L10n.text("Menu bar icon"), selection: $menuBarIconStyle) {
                    Label {
                        Text("Soniclet")
                    } icon: {
                        Image(nsImage: StatusMark.image(volume: model.outputVolume.canAdjust ? model.outputVolume.value : nil,
                                                       muted: model.outputVolume.muted) ?? NSImage())
                            .renderingMode(.template)
                    }.labelStyle(.titleAndIcon).tag(MenuBarIconStyle.soniclet)
                    Label {
                        Text(L10n.text("Connected device"))
                    } icon: {
                        Image(systemName: model.outputSymbol, variableValue: model.outputSymbolValue)
                    }.labelStyle(.titleAndIcon).tag(MenuBarIconStyle.device)
                    Label {
                        Text(L10n.text("Speaker"))
                    } icon: {
                        Image(systemName: model.volumeSymbol, variableValue: model.outputSymbolValue)
                    }.labelStyle(.titleAndIcon).tag(MenuBarIconStyle.system)
                }.pickerStyle(.menu)
                Toggle(L10n.text("Launch at login"), isOn: Binding(
                    get: { loginItem.isRequested }, set: { loginItem.setEnabled($0) }
                )).toggleStyle(.checkbox)
                if loginItem.needsApproval {
                    Text(L10n.text("Approval is required in System Settings.")).foregroundStyle(.secondary)
                    Button(L10n.text("Open Login Items Settings…")) { loginItem.openSystemSettings() }
                }
                if let error = loginItem.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
                Button(updates.menuTitle) { updates.performUserAction() }
                    .disabled(!updates.actionIsEnabled)
                    .accessibilityIdentifier("check-for-updates")
            }
            ForEach(AudioDirection.allCases, id: \.self) { direction in
                Section {
                    Toggle(L10n.text("Automatically select devices"), isOn: Binding(
                        get: { model.automaticSelectionEnabled(direction) },
                        set: { model.setAutomaticSelection($0, direction: direction) }
                    )).toggleStyle(.checkbox)
                    if model.automaticSelectionEnabled(direction), model.isManualSelection(direction) {
                        Button(L10n.text("Resume Automatic Selection")) { model.resumeAutomaticSelection(direction) }
                    }
                    let devices = model.savedDevices(direction)
                    if devices.isEmpty {
                        Text(L10n.text(direction == .output ? "No output devices" : "No input devices")).foregroundStyle(.secondary)
                    }
                    if #available(macOS 27, *) {
                        ForEach(devices) { preference in
                            DevicePreferenceRow(model: model, preference: preference)
                        }
                        .reorderable(collectionID: direction)
                    } else {
                        ForEach(devices) { preference in
                            DevicePreferenceRow(model: model, preference: preference)
                        }
                    }
                } header: {
                    Text(direction.title)
                } footer: {
                    Text([
                        L10n.text("Choose which devices appear in the menu."),
                        reorderHelp,
                        L10n.text(model.automaticSelectionEnabled(direction)
                            ? "Devices higher in the list take priority; hidden devices are excluded."
                            : "Hiding a device does not change the current input, output, or settings in other apps.")
                    ].joined(separator: " "))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .modifier(DeviceReorderContainer(model: model))
        .formStyle(.grouped)
        .frame(width: 520, height: 580)
        .onAppear { model.refresh(); loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }
}

private struct DevicePreferenceRow: View {
    @ObservedObject var model: AudioModel
    let preference: DevicePreference
    private var direction: AudioDirection { preference.key.direction }
    private var index: Int { model.savedDevices(direction).firstIndex { $0.key == preference.key } ?? 0 }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: {
                model.preferences.first { $0.key == preference.key }?.isVisible ?? true
            }, set: { model.setVisible($0, key: preference.key) })) {
                HStack(spacing: 8) {
                    Image(systemName: model.symbol(for: preference))
                        .foregroundStyle(.secondary).frame(width: 20)
                    Text(preference.name)
                    Spacer(minLength: 4)
                    if !model.isConnected(preference.key) {
                        Text(L10n.text("Not connected")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(L10n.format("Show %@ (%@)", preference.name, direction.title))
            if #available(macOS 27, *) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 24)
                    .contentShape(Rectangle())
                    .help(L10n.text("Drag devices to change their order in the menu."))
                    .accessibilityLabel(L10n.text("Drag devices to change their order in the menu."))
            }
        }
    }
    var body: some View {
        rowContent
        .contentShape(Rectangle())
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

/// SwiftUI owns the lifted row, placeholder, and pointer interaction on macOS 27.
/// Earlier systems retain the row's native Move Up/Down commands.
private struct DeviceReorderContainer: ViewModifier {
    @ObservedObject var model: AudioModel
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 27, *) {
            content.reorderContainer(for: DevicePreference.self, in: AudioDirection.self) { difference in
                let direction = difference.destination.collectionID
                let devices = model.savedDevices(direction)
                let sources = Set(difference.sources)
                guard !sources.isEmpty, sources.allSatisfy({ $0.direction == direction }),
                      sources.isSubset(of: Set(devices.map(\.key))) else { return }
                let destination: Int
                switch difference.destination.position {
                case .before(let key):
                    guard key.direction == direction,
                          let index = devices.firstIndex(where: { $0.key == key }) else { return }
                    destination = index
                case .end: destination = devices.count
                }
                let offsets = IndexSet(devices.indices.filter { sources.contains(devices[$0].key) })
                model.moveDevices(direction, from: offsets, to: destination)
            }
        } else {
            content
        }
    }
}

/// Noninteractive while Core Audio confirms the requested device.
struct PendingDeviceMenuRow: View {
    let name: String
    var body: some View {
        HStack(spacing: 9) {
            ProgressView().controlSize(.small).frame(width: 26, height: 26)
            Text(name).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }.padding(.horizontal, 12).frame(width: 304, height: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name).accessibilityValue(L10n.text("Switching"))
        .allowsHitTesting(false)
    }
}
