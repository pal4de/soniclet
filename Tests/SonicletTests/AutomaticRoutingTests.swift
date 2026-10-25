import Foundation

@main
struct AutomaticRoutingTests {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() {
        let external = DeviceKey(uid: "external", direction: .input)
        let builtIn = DeviceKey(uid: "built-in", direction: .input)
        let headset = DeviceKey(uid: "headset", direction: .input)
        var state = AutomaticRouting()
        var snapshot = RoutingSnapshot(connected: [builtIn], priority: [external, builtIn, headset], current: builtIn)
        require(state.evaluate(snapshot).selection == nil, "No redundant write")
        snapshot.connected.insert(external)
        require(state.evaluate(snapshot).selection == external, "Connected higher priority device is selected")
        state.confirmed(external); snapshot.current = external
        require(state.evaluate(snapshot).selection == nil && state.manual == nil, "Own confirmed write stays automatic")
        state.selectManually(builtIn); state.confirmed(builtIn); snapshot.current = builtIn
        require(state.evaluate(snapshot).prompt == nil, "Explicit manual choice is respected without an immediate prompt")
        snapshot.connected.remove(external)
        require(state.evaluate(snapshot).prompt == nil, "Lower/equal candidate needs no prompt")
        snapshot.connected.insert(external)
        let prompt = state.evaluate(snapshot).prompt
        require(prompt?.candidate == external && state.evaluate(snapshot).selection == nil, "Higher candidate prompts without switching")
        state.keepManual(prompt!)
        require(state.evaluate(snapshot).prompt == nil, "Decline does not repeat on refresh")
        snapshot.connected.insert(headset)
        require(state.evaluate(snapshot).prompt != nil, "A changed candidate set may prompt again")
        state.resume()
        require(state.evaluate(snapshot).selection == external, "Explicit resume applies priority")
        state.confirmed(external); snapshot.current = external
        _ = state.evaluate(snapshot)
        snapshot.current = headset
        require(state.evaluate(snapshot).selection == nil && state.manual == headset, "External default-only change is respected")
        require(state.evaluate(snapshot).prompt == nil, "External manual choice has no immediate prompt")
        snapshot.connected.remove(headset)
        require(state.evaluate(snapshot).selection == external && state.manual == nil, "Disconnected manual choice resumes automatic mode")
        var hidden = AutomaticRouting()
        _ = hidden.evaluate(snapshot)
        hidden.selectManually(builtIn); hidden.confirmed(builtIn)
        snapshot.current = builtIn; snapshot.priority = [external]
        require(hidden.evaluate(snapshot).prompt == nil, "Hidden manually chosen device is preserved")
        snapshot.current = external
        snapshot.connected.insert(headset) // OS switched while connection topology changed.
        let restore = hidden.evaluate(snapshot)
        require(restore.selection == builtIn && !restore.isAutomatic, "Restore connected manual device if OS reroutes on connection")
        var fallback = AutomaticRouting()
        let noCandidates = RoutingSnapshot(connected: [builtIn], priority: [], current: builtIn)
        require(fallback.evaluate(noCandidates).selection == nil, "No visible candidates means no write")
        var output = AutomaticRouting()
        let speaker = DeviceKey(uid: "speaker", direction: .output)
        require(output.evaluate(RoutingSnapshot(connected: [speaker], priority: [speaker], current: speaker)).selection == nil,
                "Input and output policies are independent")
        var failedAutomatic = AutomaticRouting()
        var failedSnapshot = RoutingSnapshot(connected: [external, builtIn], priority: [external, builtIn], current: builtIn)
        _ = failedAutomatic.evaluate(failedSnapshot)
        failedAutomatic.selectionFailed(failedSnapshot)
        require(failedAutomatic.manual == nil, "Failure never changes automatic mode to manual")
        require(failedAutomatic.evaluate(failedSnapshot).selection == nil, "Repeated notifications cannot retry the failed context")
        failedSnapshot.current = external
        require(failedAutomatic.evaluate(failedSnapshot).selection == nil && failedAutomatic.manual == nil,
                "Reflection after timeout must not be inferred to be a manual choice")
        failedSnapshot.current = builtIn
        _ = failedAutomatic.evaluate(failedSnapshot)
        failedSnapshot.connected.insert(headset)
        require(failedAutomatic.evaluate(failedSnapshot).selection == external, "A new connection context permits another automatic attempt")
        var failedManual = AutomaticRouting()
        _ = failedManual.evaluate(failedSnapshot)
        failedManual.selectManually(external)
        failedManual.selectionFailed(failedSnapshot)
        require(failedManual.manual == external, "Failure preserves the explicit manual target, not the observed fallback")
        failedSnapshot.current = headset
        _ = failedManual.evaluate(failedSnapshot)
        require(failedManual.manual == external, "Late fallback updates cannot replace manual intent after failure")
        var coordinated = AutomaticRouting()
        failedSnapshot.current = builtIn
        _ = coordinated.evaluate(failedSnapshot)
        failedSnapshot.current = headset
        coordinated.observed(failedSnapshot)
        require(coordinated.evaluate(failedSnapshot).selection == external && coordinated.manual == nil,
                "Input changes caused by output negotiation are observed without inventing manual intent")
        print("PASS: automatic priority, manual preservation, external defaults, prompts, decline, reconnect, hidden choices and no-candidate behavior")
    }
}
