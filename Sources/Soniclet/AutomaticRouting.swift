import Foundation

/// Pure policy. Only stable UIDs, preference order and observed defaults enter here.
struct RoutingSnapshot: Equatable {
    var connected: Set<DeviceKey>
    var priority: [DeviceKey]
    var current: DeviceKey?
    var available: [DeviceKey] { priority.filter { connected.contains($0) } }
}
struct RoutingPrompt: Equatable {
    let manual: DeviceKey
    let candidate: DeviceKey
    let available: [DeviceKey]
}
struct RoutingDecision: Equatable {
    var selection: DeviceKey?
    var isAutomatic = true
    var prompt: RoutingPrompt?
    var observedAutomaticSelection: DeviceKey?
}
struct AutomaticRouting {
    private(set) var manual: DeviceKey?
    private var previous: RoutingSnapshot?
    private var declined: RoutingPrompt?
    private var failedContext: RoutingSnapshot?
    mutating func selectManually(_ key: DeviceKey) {
        manual = key
        failedContext = nil
        // Respect the explicit choice in the current connection/order context.
        if let available = previous?.available, let candidate = available.first {
            declined = RoutingPrompt(manual: key, candidate: candidate, available: available)
        } else { declined = nil }
    }
    mutating func resume() { manual = nil; declined = nil; previous = nil; failedContext = nil }
    mutating func keepManual(_ prompt: RoutingPrompt) { declined = prompt }
    // Observing a failure or a coordinated output change is not a user choice.
    mutating func observed(_ snapshot: RoutingSnapshot) { previous = snapshot }
    mutating func selectionFailed(_ snapshot: RoutingSnapshot) {
        previous = snapshot
        failedContext = snapshot
    }
    mutating func confirmed(_ key: DeviceKey) { previous?.current = key }
    mutating func evaluate(_ snapshot: RoutingSnapshot) -> RoutingDecision {
        if let failedContext, failedContext.connected == snapshot.connected,
           failedContext.priority == snapshot.priority {
            // Late OS reflection must not be inferred to be a manual selection,
            // and default/volume notifications must not restart a failed write.
            previous = snapshot
            return RoutingDecision(selection: nil, isAutomatic: manual == nil)
        }
        failedContext = nil
        let priorCurrent = previous?.current
        let hadSnapshot = previous != nil
        if let previous, previous.available != snapshot.available { declined = nil }
        // Core Audio exposes the default, not who changed it. Treat default-only
        // changes outside Soniclet conservatively as manual selections.
        if let previous, previous.connected == snapshot.connected,
           previous.current != snapshot.current, let current = snapshot.current, manual != current {
            selectManually(current)
        }
        previous = snapshot
        if let manual, !snapshot.connected.contains(manual) { resume(); previous = snapshot }
        guard let candidate = snapshot.available.first else {
            return RoutingDecision(selection: manual != snapshot.current ? manual : nil, isAutomatic: false)
        }
        guard let manual else {
            var decision = RoutingDecision(selection: candidate == snapshot.current ? nil : candidate)
            if hadSnapshot, priorCurrent != snapshot.current, snapshot.current == candidate {
                decision.observedAutomaticSelection = candidate
            }
            return decision
        }
        var decision = RoutingDecision(selection: manual == snapshot.current ? nil : manual, isAutomatic: false)
        if let rank = snapshot.priority.firstIndex(of: manual),
           let candidateRank = snapshot.priority.firstIndex(of: candidate), candidateRank < rank {
            let prompt = RoutingPrompt(manual: manual, candidate: candidate, available: snapshot.available)
            if declined != prompt { decision.prompt = prompt }
        }
        return decision
    }
}

/// A completed automatic selection carries its destination into the temporary icon preview.
struct AutomaticSelectionEvent {
    let direction: AudioDirection
    let device: DeviceKey?
    let symbol: String
}
