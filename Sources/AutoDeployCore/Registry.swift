import Foundation

public struct PersonalAppRegistry: Codable, Equatable, Sendable {
    public var schema: Int
    public var updated: String
    public var apps: [PersonalApp]

    public static let defaultRegistryRelativePath =
        ".apple-app-tools/personal-mac-apps.json"

    public static func defaultRegistryURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["APPLE_APP_REGISTRY"], !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }
        let home = NSString(string: "~").expandingTildeInPath
        return URL(fileURLWithPath: home).appendingPathComponent(defaultRegistryRelativePath)
    }

    public static func load(from url: URL? = nil) throws -> PersonalAppRegistry {
        let target = url ?? defaultRegistryURL()
        let data = try Data(contentsOf: target)
        let decoder = JSONDecoder()
        return try decoder.decode(PersonalAppRegistry.self, from: data)
    }

    public func app(id: String) throws -> PersonalApp {
        guard let match = apps.first(where: { $0.id == id }) else {
            throw RegistryError.unknownApp(id)
        }
        return match
    }

    public var activeAutoDeployApps: [PersonalApp] {
        apps.filter { $0.status == "active" && !$0.targetMachines.isEmpty }
    }
}

public struct PersonalApp: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var platform: String
    public var scope: String
    public var status: String
    public var sourcePath: String
    public var blueprintPath: String
    public var deployCommand: String
    public var bundlePath: String
    public var requiredTools: [String]
    public var targetMachines: [String]
    public var smokeSeconds: Int?
    public var smokeCommand: [String]?
    public var requireSignedTags: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case platform
        case scope
        case status
        case sourcePath = "source_path"
        case blueprintPath = "blueprint_path"
        case deployCommand = "deploy_command"
        case bundlePath = "bundle_path"
        case requiredTools = "required_tools"
        case targetMachines = "target_machines"
        case smokeSeconds = "smoke_seconds"
        case smokeCommand = "smoke_command"
        case requireSignedTags = "require_signed_tags"
    }

    public init(
        id: String,
        name: String,
        platform: String,
        scope: String,
        status: String,
        sourcePath: String,
        blueprintPath: String,
        deployCommand: String,
        bundlePath: String,
        requiredTools: [String],
        targetMachines: [String],
        smokeSeconds: Int? = nil,
        smokeCommand: [String]? = nil,
        requireSignedTags: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.scope = scope
        self.status = status
        self.sourcePath = sourcePath
        self.blueprintPath = blueprintPath
        self.deployCommand = deployCommand
        self.bundlePath = bundlePath
        self.requiredTools = requiredTools
        self.targetMachines = targetMachines
        self.smokeSeconds = smokeSeconds
        self.smokeCommand = smokeCommand
        self.requireSignedTags = requireSignedTags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        platform = try container.decode(String.self, forKey: .platform)
        scope = try container.decode(String.self, forKey: .scope)
        status = try container.decode(String.self, forKey: .status)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        blueprintPath = try container.decode(String.self, forKey: .blueprintPath)
        deployCommand = try container.decode(String.self, forKey: .deployCommand)
        bundlePath = try container.decode(String.self, forKey: .bundlePath)
        requiredTools = try container.decode([String].self, forKey: .requiredTools)
        targetMachines = try container.decodeIfPresent([String].self, forKey: .targetMachines) ?? []
        smokeSeconds = try container.decodeIfPresent(Int.self, forKey: .smokeSeconds)
        smokeCommand = try container.decodeIfPresent([String].self, forKey: .smokeCommand)
        requireSignedTags = try container.decodeIfPresent(Bool.self, forKey: .requireSignedTags)
    }

    public var expandedSourcePath: String {
        NSString(string: sourcePath).expandingTildeInPath
    }

    public var expandedBundlePath: String {
        NSString(string: bundlePath).expandingTildeInPath
    }

    public func smokeSecondsOrDefault() -> Int {
        smokeSeconds ?? 3
    }

    public func peers(excluding localMachine: String) -> [String] {
        targetMachines.filter { $0 != localMachine }
    }
}

public enum RegistryError: Error, CustomStringConvertible {
    case unknownApp(String)

    public var description: String {
        switch self {
        case .unknownApp(let id):
            "Unknown app id in registry: \(id)"
        }
    }
}
