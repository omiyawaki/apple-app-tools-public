import Foundation

public struct VerifiedTag: Equatable, Sendable {
    public let appID: String
    public let shortSHA: String

    public init(appID: String, shortSHA: String) {
        self.appID = appID
        self.shortSHA = shortSHA
    }

    public var name: String {
        "verified/\(appID)/\(shortSHA)"
    }

    public var refPattern: String {
        "verified/\(appID)/*"
    }

    public static func shortSHA(from fullSHA: String, length: Int = 7) -> String {
        let trimmed = fullSHA.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(length))
    }

    public static func appIDPattern(for appID: String) -> String {
        "refs/tags/verified/\(appID)/*"
    }

    public static func parse(_ refOrTag: String) -> VerifiedTag? {
        let trimmed = refOrTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("refs/tags/")
            ? String(trimmed.dropFirst("refs/tags/".count))
            : trimmed
        let parts = stripped.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "verified" else { return nil }
        let appID = String(parts[1])
        let shortSHA = String(parts[2])
        guard !appID.isEmpty, !shortSHA.isEmpty else { return nil }
        return VerifiedTag(appID: appID, shortSHA: shortSHA)
    }
}
