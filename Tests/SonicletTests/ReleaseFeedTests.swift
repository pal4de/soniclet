import Foundation

private final class ReleaseStub: URLProtocol, @unchecked Sendable {
    static var status = 200
    static var payload = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct ReleaseFeedTests {
    static func require(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func payload(tag: String = "v0.10.0", url: String? = nil, draft: Bool = false, prerelease: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["tag_name": tag,
            "html_url": url ?? "https://github.com/pal4de/soniclet/releases/tag/\(tag)",
            "draft": draft, "prerelease": prerelease])
    }
    @MainActor
    static func main() async throws {
        require(ReleaseVersion("v0.10.0")! > ReleaseVersion("0.9.0")!, "Numeric minor ordering")
        require(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!, "Major ordering")
        require(ReleaseVersion("1.2.11")! > ReleaseVersion("1.2.9")!, "Patch ordering")
        for invalid in ["", "1.2", "1.2.3.4", "01.2.3", "-1.2.3", "1.2.3-beta", "1.2.3+build", "１.2.3", "9999999999999999999999999.0.0"] {
            require(ReleaseVersion(invalid) == nil, "Reject unsupported version: \(invalid)")
        }
        let feed = ReleaseFeed(repository: "pal4de/soniclet", currentVersion: "0.5.0")
        let newer = try feed.parse(payload())
        require(newer?.tag == "v0.10.0", "Find new release")
        require(try feed.parse(payload(tag: "v0.5.0")) == nil, "Equal version is not an update")
        require(try feed.parse(payload(tag: "v0.4.0")) == nil, "Older version is not an update")
        require(try feed.parse(payload(draft: true)) == nil, "Ignore drafts")
        require(try feed.parse(payload(prerelease: true)) == nil, "Ignore prereleases")
        for url in ["http://github.com/pal4de/soniclet/releases/tag/v0.10.0",
                    "https://github.com.evil.invalid/pal4de/soniclet/releases/tag/v0.10.0",
                    "https://github.com/someone/soniclet/releases/tag/v0.10.0",
                    "https://github.com/pal4de/soniclet/releases/tag/v99.0.0",
                    "https://name@github.com/pal4de/soniclet/releases/tag/v0.10.0",
                    "https://github.com:443/pal4de/soniclet/releases/tag/v0.10.0",
                    "https://github.com/pal4de/soniclet/releases/tag/v0.10.0?next=elsewhere"] {
            do { _ = try feed.parse(payload(url: url)); require(false, "Reject unexpected release URL") } catch {}
        }
        require(!feed.isNewerAndValid(GitHubRelease(tag: "invalid", url: URL(string: "https://github.com")!)), "Reject invalid cached release")
        require(ReleaseFeed(repository: "../elsewhere", currentVersion: "0.5.0").request == nil, "Reject invalid repository")
        require(feed.request?.timeoutInterval == 15, "Bounded network timeout")
        require(feed.request?.value(forHTTPHeaderField: "Authorization") == nil, "No credentials in update request")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        ReleaseStub.payload = try payload()
        require(try await feed.latest(session: session) == newer, "Decode HTTP response")
        ReleaseStub.status = 404
        require(try await feed.latest(session: session) == nil, "No first release is a normal result")
        for status in [403, 429, 500] {
            ReleaseStub.status = status
            do { _ = try await feed.latest(session: session); require(false, "Reject HTTP \(status)") } catch {}
        }
        ReleaseStub.status = 200; ReleaseStub.payload = Data("not JSON".utf8)
        do { _ = try await feed.latest(session: session); require(false, "Reject malformed response") } catch {}
        let domain = "Soniclet.update-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        ReleaseStub.payload = try payload()
        let checker = UpdateChecker(defaults: defaults, feed: feed, session: session)
        try await checker.check(force: false)
        require(checker.release == newer && !checker.isChecking, "Publish checked release and finish checking")
        let relaunched = UpdateChecker(defaults: defaults, feed: feed, session: session)
        require(relaunched.release == newer, "Available-release notice survives restart")
        ReleaseStub.status = 500
        try await relaunched.check(force: false)
        require(relaunched.release == newer, "Throttle automatic requests for 24 hours")
        do { try await relaunched.check(force: true); require(false, "Manual check bypasses throttle") } catch {}
        require(!relaunched.isChecking && relaunched.release == newer, "Failure keeps validated notice and resets busy state")
        let upgradedFeed = ReleaseFeed(repository: "pal4de/soniclet", currentVersion: "1.0.0")
        require(UpdateChecker(defaults: defaults, feed: upgradedFeed, session: session).release == nil, "Do not show stale notice after upgrading")
        ReleaseStub.status = 200; ReleaseStub.payload = try payload(tag: "v0.5.0")
        try await relaunched.check(force: true)
        require(relaunched.release == nil, "Clear notice when no newer release remains")
        require(UpdateChecker(defaults: defaults, feed: feed, session: session).release == nil, "Clear persisted notice as well")
        print("PASS: release versions, URL validation, HTTP failures, caching, restart, upgrade, 24-hour throttle and manual override (offline fixtures)")
    }
}
