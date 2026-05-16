import Foundation

public struct DeployPaths: Sendable {
    public let home: URL

    public init(home: URL? = nil) {
        self.home = home ?? URL(fileURLWithPath: NSString(string: "~").expandingTildeInPath)
    }

    public var stateRoot: URL {
        home.appendingPathComponent(".apple-app-tools", isDirectory: true)
    }

    public var deployCheckoutsRoot: URL {
        stateRoot.appendingPathComponent("deploy-checkouts", isDirectory: true)
    }

    public func deployCheckout(forAppID id: String) -> URL {
        deployCheckoutsRoot.appendingPathComponent(id, isDirectory: true)
    }

    public var cooldownsRoot: URL {
        stateRoot.appendingPathComponent("cooldowns", isDirectory: true)
    }

    public func cooldownFile(forAppID id: String) -> URL {
        cooldownsRoot.appendingPathComponent("\(id).tag")
    }

    public var logsRoot: URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("apple-app-tools", isDirectory: true)
    }

    public var autoDeployLog: URL {
        logsRoot.appendingPathComponent("auto-deploy.log")
    }

    public var launchAgentsRoot: URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }
}

public struct CooldownStore: Sendable {
    public let paths: DeployPaths

    public init(paths: DeployPaths = DeployPaths()) {
        self.paths = paths
    }

    public func currentlySuppressedTag(forAppID id: String) -> String? {
        let file = paths.cooldownFile(forAppID: id)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let content = String(data: data, encoding: .utf8) ?? ""
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func recordFailure(appID: String, tag: String) throws {
        try FileManager.default.createDirectory(at: paths.cooldownsRoot, withIntermediateDirectories: true)
        let file = paths.cooldownFile(forAppID: appID)
        try tag.write(to: file, atomically: true, encoding: .utf8)
    }

    public func clear(appID: String) {
        try? FileManager.default.removeItem(at: paths.cooldownFile(forAppID: appID))
    }

    public func isSuppressed(appID: String, tag: String) -> Bool {
        guard let current = currentlySuppressedTag(forAppID: appID) else { return false }
        return current == tag
    }
}
