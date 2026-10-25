import AppKit
import Combine

@MainActor
final class AudioModel: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var preferences: [DevicePreference] = []
    @Published private(set) var outputID: UInt32 = 0
    @Published private(set) var inputID: UInt32 = 0
    @Published private(set) var outputVolume = OutputVolume(value: 0, channels: [], muteElement: nil, muted: false)
    @Published var errorMessage: String?
    @Published private(set) var pendingSelection: DeviceKey?
    @Published private(set) var accessories: [AudioAccessory] = []
    private var accessoryRefresh: Task<Void, Never>?
    private var accessoryRefreshDate = Date.distantPast
    private var accessorySignature = Set<String>()
    private let service = CoreAudioService()
    private let store: DevicePreferences
    private var observedOutput: UInt32?
    private var refreshWork: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?
    private var selectionRequest = UUID()

    init(store: DevicePreferences = DevicePreferences()) {
        self.store = store
        refresh()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.refresh(forceObservation: true) }
        }
    }

    func refresh(forceObservation: Bool = false) {
        do {
            let discovered = try service.devices()
            devices = discovered
            store.synchronize(discovered)
            preferences = store.devices
            outputID = service.defaultDevice(.output)
            inputID = service.defaultDevice(.input)
            outputVolume = service.volume(outputID)
            if observedOutput != outputID || forceObservation {
                observedOutput = outputID
                service.observe(outputID: outputID) { [weak self] in
                    DispatchQueue.main.async { self?.scheduleRefresh() }
                }
            }
            refreshAccessoriesIfNeeded()
        } catch { errorMessage = error.localizedDescription }
    }

    var bluetoothOutputs: [AudioDevice] {
        devices.filter { $0.key.direction == .output && $0.isBluetooth }
    }
    func accessory(for device: AudioDevice) -> AudioAccessory? {
        guard device.isBluetooth else { return nil }
        return AudioAccessory.match(uid: device.key.uid, name: device.name, in: accessories)
    }
    var hasAppleHeadphones: Bool {
        bluetoothOutputs.contains { accessory(for: $0)?.isApple == true }
    }
    func refreshAccessoriesIfNeeded() {
        #if !SETTINGS_SMOKE_TEST
        guard !bluetoothOutputs.isEmpty else { accessories = []; return }
        let signature = Set(bluetoothOutputs.map { $0.key.uid }).union(["output:\(outputID)"])
        guard accessoryRefresh == nil,
              signature != accessorySignature || Date().timeIntervalSince(accessoryRefreshDate) >= 60 else { return }
        accessorySignature = signature
        accessoryRefreshDate = Date()
        accessoryRefresh = Task { [weak self] in
            let entries = await Task.detached(priority: .utility) { (try? AudioAccessory.readConnected()) ?? [] }.value
            guard let self else { return }
            self.accessories = entries
            self.accessoryRefresh = nil
        }
        #endif
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func visibleDevices(_ direction: AudioDirection) -> [AudioDevice] {
        devices.filter { $0.key.direction == direction && store.isVisible($0.key) }
    }
    func selected(_ device: AudioDevice) -> Bool {
        device.objectID == (device.key.direction == .output ? outputID : inputID)
    }
    func hiddenCurrentDevice(_ direction: AudioDirection) -> AudioDevice? {
        devices.first { $0.key.direction == direction && selected($0) && !store.isVisible($0.key) }
    }
    func isConnected(_ key: DeviceKey) -> Bool { devices.contains { $0.key == key } }
    func savedDevices(_ direction: AudioDirection) -> [DevicePreference] {
        preferences.filter { $0.key.direction == direction }.sorted {
            if isConnected($0.key) != isConnected($1.key) { return isConnected($0.key) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func setVisible(_ visible: Bool, key: DeviceKey) {
        store.setVisible(visible, for: key)
        preferences = store.devices
    }
    func select(_ device: AudioDevice) {
        errorMessage = nil
        selectionRequest = UUID()
        let request = selectionRequest
        do {
            try service.setDefault(device)
            pendingSelection = device.key
            // Core Audio property writes are asynchronous. Read back instead of showing an optimistic checkmark.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self, self.selectionRequest == request else { return }
                self.refresh()
                if self.selected(device) { self.pendingSelection = nil; return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                    guard let self, self.selectionRequest == request else { return }
                    self.refresh()
                    self.pendingSelection = nil
                    if !self.selected(device) { self.errorMessage = L10n.format("Could not switch to %@. Please try again.", device.name) }
                }
            }
        } catch { pendingSelection = nil; errorMessage = error.localizedDescription; refresh() }
    }
    func changeVolume(_ value: Float) {
        do {
            try service.setVolume(value, on: outputID, controls: outputVolume)
            outputVolume = service.volume(outputID)
        } catch { errorMessage = error.localizedDescription; refresh() }
    }
    func stepVolume(up: Bool) {
        refresh()
        guard outputVolume.canAdjust else { return }
        let step: Float = 1.0 / 16.0
        changeVolume(max(0, min(1, outputVolume.value + (up ? step : -step))))
    }
    func toggleOutputMute() {
        refresh()
        do {
            try service.setMuted(!outputVolume.muted, on: outputID, controls: outputVolume)
        } catch { errorMessage = error.localizedDescription }
        refresh()
    }
    var outputSymbol: String {
        if let output = devices.first(where: { $0.key.direction == .output && $0.objectID == outputID }),
           output.symbol == "headphones" { return "headphones" }
        return outputVolume.muted || (outputVolume.canAdjust && outputVolume.value <= 0)
            ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }
    var outputSymbolValue: Double {
        guard outputVolume.canAdjust, outputVolume.value.isFinite else { return 1 }
        return Double(max(0, min(1, outputVolume.value)))
    }
    var outputName: String { devices.first { $0.key.direction == .output && $0.objectID == outputID }?.name ?? L10n.text("Not connected") }
    var inputName: String { devices.first { $0.key.direction == .input && $0.objectID == inputID }?.name ?? L10n.text("Not connected") }
}
