import Foundation

/// Stable SemVer only: release tags are vMAJOR.MINOR.PATCH (or without v).
struct ReleaseVersion: Comparable, Codable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part.count == 1 || part.first != "0" else { return nil }
            return Int(part)
        }
        guard numbers.count == 3 else { return nil }
        major = numbers[0]; minor = numbers[1]; patch = numbers[2]
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

struct GitHubRelease: Codable, Equatable {
    let tag: String
    let url: URL
}

struct ReleaseFeed {
    enum Failure: Error { case invalidConfiguration, invalidResponse, invalidRelease }
    let repository: String
    let currentVersion: String

    var request: URLRequest? {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." &&
            $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }), ReleaseVersion(currentVersion) != nil,
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Soniclet/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        return request
    }

    func isNewerAndValid(_ release: GitHubRelease) -> Bool {
        guard let version = ReleaseVersion(release.tag), let current = ReleaseVersion(currentVersion),
              version > current, let components = URLComponents(url: release.url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == "https" && components.host == "github.com" && components.port == nil &&
            components.user == nil && components.password == nil && components.query == nil && components.fragment == nil &&
            components.path == "/\(repository)/releases/tag/\(release.tag)"
    }

    func parse(_ data: Data) throws -> GitHubRelease? {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: URL
            let draft: Bool
            let prerelease: Bool
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard !payload.draft, !payload.prerelease else { return nil }
        guard let version = ReleaseVersion(payload.tag_name), let current = ReleaseVersion(currentVersion) else {
            throw Failure.invalidRelease
        }
        guard version > current else { return nil }
        let release = GitHubRelease(tag: payload.tag_name, url: payload.html_url)
        guard isNewerAndValid(release) else { throw Failure.invalidRelease }
        return release
    }

    func latest(session: URLSession = .shared) async throws -> GitHubRelease? {
        guard let request else { throw Failure.invalidConfiguration }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if response.statusCode == 404 { return nil } // A repository can have no releases yet.
        guard response.statusCode == 200 else { throw Failure.invalidResponse }
        return try parse(data)
    }
}
