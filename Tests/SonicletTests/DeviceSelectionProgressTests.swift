import Foundation

@main
struct DeviceSelectionProgressTests {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() {
        let target = DeviceKey(uid: "usb-mic", direction: .input)
        let old = DeviceKey(uid: "bluetooth-mic", direction: .input)
        let connected: Set<DeviceKey> = [target, old]
        var delayed = DeviceSelectionProgress(target: target, startedAt: 0)
        require(delayed.observe(current: old, connected: connected, now: 1.1) == .waiting, "A slow change is not failed at one second")
        require(delayed.observe(current: target, connected: connected, now: 2) == .waiting, "First match is not yet stable")
        require(delayed.observe(current: target, connected: connected, now: 2.6) == .confirmed, "Late stable change succeeds")
        var bouncing = DeviceSelectionProgress(target: target, startedAt: 0)
        _ = bouncing.observe(current: target, connected: connected, now: 0.1)
        require(bouncing.observe(current: old, connected: connected, now: 0.4) == .waiting, "An OS override resets settling")
        _ = bouncing.observe(current: target, connected: connected, now: 1.2)
        require(bouncing.observe(current: target, connected: connected, now: 1.5) == .waiting, "A transient match cannot complete the request")
        require(bouncing.observe(current: target, connected: connected, now: 1.8) == .confirmed, "A subsequent stable match completes")
        var timedOut = DeviceSelectionProgress(target: target, startedAt: 10)
        require(timedOut.observe(current: old, connected: connected, now: 14.9) == .waiting, "Wait through the bounded reflection period")
        require(timedOut.observe(current: old, connected: connected, now: 15.1) == .timedOut, "An unchanged default eventually times out")
        var disconnected = DeviceSelectionProgress(target: target, startedAt: 0)
        require(disconnected.observe(current: old, connected: [old], now: 0.2) == .disconnected, "Disconnect is a topology event, not a timeout")
        var nearDeadline = DeviceSelectionProgress(target: target, startedAt: 0)
        _ = nearDeadline.observe(current: target, connected: connected, now: 4.9)
        require(nearDeadline.observe(current: target, connected: connected, now: 5.5) == .confirmed, "A match near the deadline gets its settling interval")
        print("PASS: delayed reflection, stable confirmation, transient overrides, bounded timeout and disconnect")
    }
}
