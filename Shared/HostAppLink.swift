import Foundation

/// Only two fixed, user-initiated recovery actions can cross this URL boundary.
enum HostAppLink {
    enum Action: String { case open, safariSettings = "safari-settings" }

    static func url(_ action: Action, extensionIdentifier: String?) -> URL? {
        guard let identifier = extensionIdentifier,
              let suffix = [".widget", ".safari"].first(where: { identifier.hasSuffix($0) }) else { return nil }
        let host = String(identifier.dropLast(suffix.count))
        guard host.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil else { return nil }
        var parts = URLComponents()
        parts.scheme = host
        parts.host = action.rawValue
        return parts.url
    }

    static func action(for url: URL, hostIdentifier: String) -> Action? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == hostIdentifier.lowercased(),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let host = parts.host else { return nil }
        return Action(rawValue: host)
    }
}
