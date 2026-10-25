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
        print("PASS: automatic priority, manual preservation, external defaults, prompts, decline, reconnect, hidden choices and no-candidate behavior")
    }
}
