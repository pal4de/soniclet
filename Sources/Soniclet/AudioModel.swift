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
    @Published private(set) var pendingSelections = Set<DeviceKey>()
    @Published private(set) var accessories: [AudioAccessory] = []
    private var accessoryRefresh: Task<Void, Never>?
    private var accessoryRefreshDate = Date.distantPast
    private var accessorySignature = Set<String>()
    private let service = CoreAudioService()
    private let store: DevicePreferences
    private var observedOutput: UInt32?
    private var refreshWork: DispatchWorkItem?
    private var wakeObserver: NSObjectProtocol?
    private struct SelectionRequest {
        let device: AudioDevice
        let automatically: Bool
        var progress: DeviceSelectionProgress
    }
    private var selectionRequests: [AudioDirection: SelectionRequest] = [:]
    private var selectionCheck: DispatchWorkItem?
    private var selectionErrorTarget: DeviceKey?
    private var routing: [AudioDirection: AutomaticRouting] = [:]
    private let defaults: UserDefaults
    @Published private(set) var automaticDirections: Set<AudioDirection> = []
    @Published private(set) var routingPrompts: [AudioDirection: RoutingPrompt] = [:]
    let automaticSelections = PassthroughSubject<AutomaticSelectionEvent, Never>()
    // Use the installed volume-key sound without bundling Apple's audio asset.
    // Its location is not a public API contract; omit feedback if unavailable.
    private let feedbackSound = NSSound(contentsOf: URL(fileURLWithPath:
        "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"), byReference: true)
    private var feedbackDate = Date.distantPast

    init(store: DevicePreferences = DevicePreferences(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        #if !SETTINGS_SMOKE_TEST
        automaticDirections = Set(AudioDirection.allCases.filter { defaults.bool(forKey: "automaticSelection." + $0.rawValue) })
        #endif
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
            checkPendingSelections()
            if let target = selectionErrorTarget,
               routingSnapshot(target.direction).current == target || !devices.contains(where: { $0.key == target }) {
                errorMessage = nil
                selectionErrorTarget = nil
            }
            reconcileAutomaticSelection()
        } catch {
            for request in Array(selectionRequests.values) { failSelection(request.device) }
            errorMessage = error.localizedDescription
        }
        scheduleSelectionCheck()
    }

    var outputIsAirPlay: Bool {
        devices.contains { $0.key.direction == .output && $0.objectID == outputID && $0.isAirPlay }
    }
    var bluetoothOutputs: [AudioDevice] {
        devices.filter { $0.key.direction == .output && $0.isBluetooth }
    }
    func accessory(for device: AudioDevice) -> AudioAccessory? {
        guard device.isBluetooth else { return nil }
        return AudioAccessory.match(uid: device.key.uid, name: device.name, in: accessories)
    }
    func symbol(for device: AudioDevice) -> String {
        let entry = accessory(for: device)
        let candidate = device.key.direction == .input && entry?.isHeadphone == false
            ? device.symbol : entry?.symbol ?? device.symbol
        return availableSymbol(candidate)
    }
    func symbol(for preference: DevicePreference) -> String {
        if let device = devices.first(where: { $0.key == preference.key }) { return symbol(for: device) }
        return availableSymbol(preference.symbol)
    }
    private func availableSymbol(_ candidate: String) -> String {
        NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil ? candidate : DeviceSymbols.fallback(for: candidate)
    }
    var appleHeadphones: AudioAccessory? {
        let ordered = bluetoothOutputs.sorted {
            if selected($0) != selected($1) { return selected($0) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return ordered.compactMap { accessory(for: $0) }.first { $0.isApple && $0.isHeadphone && $0.address != nil }
    }
    func refreshAccessoriesIfNeeded() {
        #if !SETTINGS_SMOKE_TEST
        guard !bluetoothOutputs.isEmpty else {
            accessoryRefresh?.cancel()
            accessoryRefresh = nil
            accessories = []
            accessorySignature = []
            accessoryRefreshDate = .distantPast
            return
        }
        let signature = Set(bluetoothOutputs.map { $0.key.uid }).union(["output:\(outputID)"])
        if accessoryRefresh != nil && signature != accessorySignature {
            accessoryRefresh?.cancel()
            accessoryRefresh = nil
        }
        guard accessoryRefresh == nil,
              signature != accessorySignature || Date().timeIntervalSince(accessoryRefreshDate) >= 60 else { return }
        accessorySignature = signature
        accessoryRefreshDate = Date()
        accessoryRefresh = Task { [weak self] in
            let entries = await Task.detached(priority: .utility) { (try? AudioAccessory.readConnected()) ?? [] }.value
            guard let self, !Task.isCancelled, self.accessorySignature == signature else { return }
            self.accessories = entries
            self.accessoryRefresh = nil
        }
        #endif
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func visibleDevices(_ direction: AudioDirection) -> [AudioDevice] {
        let connected = Dictionary(uniqueKeysWithValues: devices.map { ($0.key, $0) })
        return store.orderedDevices(direction).filter { $0.isVisible }.compactMap { connected[$0.key] }
    }
    func selected(_ device: AudioDevice) -> Bool {
        device.objectID == (device.key.direction == .output ? outputID : inputID)
    }
    func hiddenCurrentDevice(_ direction: AudioDirection) -> AudioDevice? {
        devices.first { $0.key.direction == direction && selected($0) && !store.isVisible($0.key) }
    }
    func isConnected(_ key: DeviceKey) -> Bool { devices.contains { $0.key == key } }
    func savedDevices(_ direction: AudioDirection) -> [DevicePreference] {
        store.orderedDevices(direction)
    }
    func moveDevices(_ direction: AudioDirection, from offsets: IndexSet, to destination: Int) {
        store.move(direction, from: offsets, to: destination)
        preferences = store.devices
        reconcileAutomaticSelection()
    }
    @discardableResult
    func moveDevice(_ key: DeviceKey, relativeTo target: DeviceKey, after: Bool) -> Bool {
        guard key != target, key.direction == target.direction else { return false }
        let ordered = savedDevices(key.direction)
        guard let source = ordered.firstIndex(where: { $0.key == key }),
              let destination = ordered.firstIndex(where: { $0.key == target }) else { return false }
        moveDevices(key.direction, from: IndexSet(integer: source), to: destination + (after ? 1 : 0))
        return true
    }
    func setVisible(_ visible: Bool, key: DeviceKey) {
        store.setVisible(visible, for: key)
        preferences = store.devices
        reconcileAutomaticSelection()
    }
    func select(_ device: AudioDevice, automatically: Bool = false, userInitiated: Bool = true) {
        if userInitiated {
            routing[device.key.direction, default: AutomaticRouting()].selectManually(device.key)
            routingPrompts.removeValue(forKey: device.key.direction)
        }
        guard !pendingSelections.contains(device.key) else { return }
        // A newer explicit choice supersedes any pending request in this direction.
        selectionRequests.removeValue(forKey: device.key.direction)
        pendingSelections = Set(selectionRequests.values.map { $0.device.key })
        guard service.defaultDevice(device.key.direction) != device.objectID else { return }
        errorMessage = nil
        selectionErrorTarget = nil
        let request = SelectionRequest(device: device, automatically: automatically,
            progress: DeviceSelectionProgress(target: device.key, startedAt: ProcessInfo.processInfo.systemUptime))
        selectionRequests[device.key.direction] = request
        do {
            try service.setDefault(device)
            pendingSelections.insert(device.key)
            scheduleSelectionCheck()
        } catch {
            failSelection(device)
            errorMessage = error.localizedDescription
        }
    }
    private func scheduleSelectionCheck() {
        selectionCheck?.cancel()
        guard !selectionRequests.isEmpty else { selectionCheck = nil; return }
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        selectionCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
    private func checkPendingSelections() {
        for direction in AudioDirection.allCases {
            guard var request = selectionRequests[direction] else { continue }
            let snapshot = routingSnapshot(direction)
            let outcome = request.progress.observe(current: snapshot.current, connected: snapshot.connected,
                now: ProcessInfo.processInfo.systemUptime)
            selectionRequests[direction] = request
            switch outcome {
            case .waiting: break
            case .confirmed: finishSelection(request.device, automatically: request.automatically)
            case .disconnected:
                selectionRequests.removeValue(forKey: direction)
                pendingSelections.remove(request.device.key)
                routing[direction, default: AutomaticRouting()].observed(snapshot)
                if direction == .output { routing[.input, default: AutomaticRouting()].observed(routingSnapshot(.input)) }
                // A disappearing candidate is a topology update; evaluate the remaining candidates.
            case .timedOut:
                failSelection(request.device)
                errorMessage = L10n.format("Could not confirm the switch to %@. Please try again.", request.device.name)
            }
        }
    }
    func automaticSelectionEnabled(_ direction: AudioDirection) -> Bool { automaticDirections.contains(direction) }
    func setAutomaticSelection(_ enabled: Bool, direction: AudioDirection) {
        if enabled { automaticDirections.insert(direction) } else { automaticDirections.remove(direction) }
        defaults.set(enabled, forKey: "automaticSelection." + direction.rawValue)
        routing[direction] = AutomaticRouting()
        routingPrompts.removeValue(forKey: direction)
        refresh()
    }
    func isManualSelection(_ direction: AudioDirection) -> Bool { routing[direction]?.manual != nil }
    func isManuallySelected(_ device: AudioDevice) -> Bool {
        selected(device) && (!automaticSelectionEnabled(device.key.direction) || routing[device.key.direction]?.manual == device.key)
    }
    var manuallyOverriddenDirections: [AudioDirection] {
        AudioDirection.allCases.filter { automaticSelectionEnabled($0) && isManualSelection($0) }
    }
    func resumeAllAutomaticSelections() {
        for direction in manuallyOverriddenDirections {
            routing[direction, default: AutomaticRouting()].resume()
            routingPrompts.removeValue(forKey: direction)
        }
        refresh()
    }
    func resumeAutomaticSelection(_ direction: AudioDirection) {
        routing[direction, default: AutomaticRouting()].resume()
        refresh()
    }
    func resolveRoutingPrompt(_ prompt: RoutingPrompt, resume: Bool) {
        let direction = prompt.manual.direction
        refresh()
        guard routingPrompts[direction] == prompt else { return }
        if resume { routing[direction, default: AutomaticRouting()].resume() }
        else { routing[direction, default: AutomaticRouting()].keepManual(prompt) }
        routingPrompts.removeValue(forKey: direction)
        reconcileAutomaticSelection()
    }
    private func routingSnapshot(_ direction: AudioDirection) -> RoutingSnapshot {
        RoutingSnapshot(connected: Set(devices.filter { $0.key.direction == direction }.map(\.key)),
            priority: savedDevices(direction).filter(\.isVisible).map(\.key),
            current: devices.first { $0.key.direction == direction && selected($0) }?.key)
    }
    private func reconcileAutomaticSelection() {
        for direction in AudioDirection.allCases where automaticDirections.contains(direction) {
            // Settle one request before issuing another automatic write.
            guard selectionRequests.isEmpty else { continue }
            let snapshot = routingSnapshot(direction)
            let decision = routing[direction, default: AutomaticRouting()].evaluate(snapshot)
            if routingPrompts[direction] != decision.prompt { routingPrompts[direction] = decision.prompt }
            if let key = decision.observedAutomaticSelection,
               let device = devices.first(where: { $0.key == key }) { reportAutomaticSelection(device) }
            if let key = decision.selection, let device = devices.first(where: { $0.key == key }) {
                select(device, automatically: decision.isAutomatic, userInitiated: false)
            }
        }
    }
    private func finishSelection(_ device: AudioDevice, automatically: Bool) {
        selectionRequests.removeValue(forKey: device.key.direction)
        pendingSelections.remove(device.key)
        routing[device.key.direction, default: AutomaticRouting()].confirmed(device.key)
        if device.key.direction == .output {
            routing[.input, default: AutomaticRouting()].observed(routingSnapshot(.input))
        }
        if automatically { reportAutomaticSelection(device) }
    }
    private func reportAutomaticSelection(_ device: AudioDevice) {
        automaticSelections.send(AutomaticSelectionEvent(direction: device.key.direction,
            device: device.key, symbol: device.key.direction == .output ? symbol(for: device) : volumeSymbol))
    }
    private func failSelection(_ device: AudioDevice) {
        selectionRequests.removeValue(forKey: device.key.direction)
        pendingSelections.remove(device.key)
        selectionErrorTarget = device.key
        // Suppress retries for this connection/order context without changing mode.
        routing[device.key.direction, default: AutomaticRouting()].selectionFailed(routingSnapshot(device.key.direction))
        routingPrompts.removeValue(forKey: device.key.direction)
        if device.key.direction == .output {
            routing[.input, default: AutomaticRouting()].observed(routingSnapshot(.input))
        }
    }
    func changeVolume(_ value: Float) {
        guard outputVolume.canAdjust, value.isFinite else { return }
        do {
            try service.setVolume(value, on: outputID, controls: outputVolume)
            outputVolume = service.volume(outputID)
        } catch { errorMessage = error.localizedDescription; refresh() }
    }
    func stepVolume(up: Bool) {
        refresh()
        guard outputVolume.canAdjust else { return }
        let step: Float = 1.0 / 16.0
        let previous = outputVolume.value
        changeVolume(max(0, min(1, previous + (up ? step : -step))))
        if outputVolume.value != previous { playVolumeFeedback() }
    }
    func playVolumeFeedback() {
        guard outputVolume.canAdjust, !outputVolume.muted, outputVolume.value > 0,
              Date().timeIntervalSince(feedbackDate) > 0.1 else { return }
        feedbackDate = Date()
        feedbackSound?.stop()
        feedbackSound?.playbackDeviceIdentifier = devices.first { $0.key.direction == .output && $0.objectID == outputID }?.key.uid
        feedbackSound?.play()
    }
    func toggleOutputMute() {
        refresh()
        do {
            try service.setMuted(!outputVolume.muted, on: outputID, controls: outputVolume)
        } catch { errorMessage = error.localizedDescription }
        refresh()
    }
    var outputSymbol: String {
        guard let output = devices.first(where: { $0.key.direction == .output && $0.objectID == outputID }) else { return volumeSymbol }
        return symbol(for: output)
    }
    var volumeSymbol: String {
        outputVolume.muted || (outputVolume.canAdjust && outputVolume.value <= 0)
            ? "speaker.slash.fill" : "speaker.wave.3.fill"
    }
    var outputSymbolValue: Double {
        guard outputVolume.canAdjust, outputVolume.value.isFinite else { return 1 }
        return Double(max(0, min(1, outputVolume.value)))
    }
    var outputName: String { devices.first { $0.key.direction == .output && $0.objectID == outputID }?.name ?? L10n.text("Not connected") }
    var inputName: String { devices.first { $0.key.direction == .input && $0.objectID == inputID }?.name ?? L10n.text("Not connected") }
}
