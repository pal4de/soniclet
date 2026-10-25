import Foundation

private final class NoNetwork: URLProtocol, @unchecked Sendable {
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@main
struct StoreUpdateTests {
    @MainActor
    static func main() async throws {
        let domain = "Soniclet.store-update-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let release = GitHubRelease(tag: "v99.0.0", url: URL(string: "https://github.com/pal4de/soniclet/releases/tag/v99.0.0")!)
        defaults.set(try JSONEncoder().encode(release), forKey: "updates.availableRelease")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NoNetwork.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let updates = UpdateChecker(defaults: defaults,
            feed: ReleaseFeed(repository: "pal4de/soniclet", currentVersion: "0.7.5"), session: session)
        updates.checkIfDue()
        try await updates.check(force: true)
        guard updates.release == nil, !updates.isChecking, updates.actionIsEnabled,
              updates.menuTitle == L10n.text("App Store…"), NoNetwork.requests == 0,
              defaults.object(forKey: "updates.lastAttempt") == nil else {
            fputs("FAIL: Store build must ignore GitHub cache and never request GitHub updates\n", stderr)
            exit(1)
        }
        print("PASS: App Store update policy, ignored GitHub cache and no automatic/manual GitHub requests")
    }
}
