import Foundation

/// Observe a requested default by stable UID, using monotonic time. No hardware writes or retries.
struct DeviceSelectionProgress {
    enum Outcome: Equatable { case waiting, confirmed, disconnected, timedOut }
    let target: DeviceKey
    let deadline: TimeInterval
    private var matchedSince: TimeInterval?
    init(target: DeviceKey, startedAt: TimeInterval) {
        self.target = target
        deadline = startedAt + 5
    }
    mutating func observe(current: DeviceKey?, connected: Set<DeviceKey>, now: TimeInterval) -> Outcome {
        guard connected.contains(target) else { return .disconnected }
        if current == target {
            if let matchedSince, now - matchedSince >= 0.5 { return .confirmed }
            if matchedSince == nil { matchedSince = now }
            return .waiting
        }
        matchedSince = nil
        return now >= deadline ? .timedOut : .waiting
    }
}
