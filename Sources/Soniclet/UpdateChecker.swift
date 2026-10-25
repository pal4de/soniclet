import AppKit
import Combine

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var release: GitHubRelease?
    @Published private(set) var isChecking = false
    private let feed: ReleaseFeed
    private let defaults: UserDefaults
    private let session: URLSession
    private let lastAttemptKey = "updates.lastAttempt"
    private let cachedReleaseKey = "updates.availableRelease"

    init(defaults: UserDefaults = .standard, feed: ReleaseFeed? = nil, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        self.feed = feed ?? ReleaseFeed(repository: Bundle.main.object(forInfoDictionaryKey: "GitHubRepository") as? String ?? "",
                           currentVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        #if !MAC_APP_STORE
        if let data = defaults.data(forKey: cachedReleaseKey),
           let cached = try? JSONDecoder().decode(GitHubRelease.self, from: data), self.feed.isNewerAndValid(cached) {
            release = cached
        }
        #endif
    }

    var menuTitle: String {
        #if MAC_APP_STORE
        return L10n.text("App Store…")
        #else
        if let release { return L10n.format("Version %@ is available…", release.tag) }
        return L10n.text(isChecking ? "Checking for Updates…" : "Check for Updates…")
        #endif
    }
    var actionIsEnabled: Bool { release != nil || !isChecking }

    func checkIfDue() {
        #if !SETTINGS_SMOKE_TEST && !MAC_APP_STORE
        Task { try? await check(force: false) }
        #endif
    }

    func check(force: Bool) async throws {
        #if MAC_APP_STORE
        return
        #else
        guard !isChecking else { return }
        if !force, let date = defaults.object(forKey: lastAttemptKey) as? Date,
           Date().timeIntervalSince(date) < 24 * 60 * 60 { return }
        defaults.set(Date(), forKey: lastAttemptKey)
        isChecking = true
        defer { isChecking = false }
        let latest = try await feed.latest(session: session)
        release = latest
        if let latest {
            defaults.set(try JSONEncoder().encode(latest), forKey: cachedReleaseKey)
        } else { defaults.removeObject(forKey: cachedReleaseKey) }
        #endif
    }

    /// Called after menu tracking ends. Automatic checks never show alerts.
    func performUserAction() {
        #if MAC_APP_STORE
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.AppStore") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let release, feed.isNewerAndValid(release) {
            NSWorkspace.shared.open(release.url)
            return
        }
        guard !isChecking else { return }
        Task {
            let message: String
            do {
                try await check(force: true)
                message = release.map { L10n.format("Version %@ is available…", $0.tag) }
                    ?? L10n.text("No newer release is available.")
            } catch { message = L10n.text("Could not check for updates. Try again later.") }
            let alert = NSAlert()
            alert.messageText = "Soniclet"
            alert.informativeText = message
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        #endif
    }
}
