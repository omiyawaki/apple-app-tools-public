import Foundation

public struct AppBlueprint: Codable, Equatable {
    public var schemaVersion: Int
    public var app: AppIdentity
    public var build: BuildConfiguration
    public var packageDependencies: [PackageDependency]
    public var components: [ComponentUse]
    public var localModules: [LocalModule]
    public var fingerprint: FingerprintConfiguration
    public var customCode: CustomCodePolicy

    public init(
        schemaVersion: Int,
        app: AppIdentity,
        build: BuildConfiguration,
        packageDependencies: [PackageDependency],
        components: [ComponentUse],
        localModules: [LocalModule],
        fingerprint: FingerprintConfiguration,
        customCode: CustomCodePolicy
    ) {
        self.schemaVersion = schemaVersion
        self.app = app
        self.build = build
        self.packageDependencies = packageDependencies
        self.components = components
        self.localModules = localModules
        self.fingerprint = fingerprint
        self.customCode = customCode
    }

    public static func load(from url: URL) throws -> AppBlueprint {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try BlueprintYAMLParser().parse(text)
    }
}

public struct AppIdentity: Codable, Equatable {
    public var id: String
    public var name: String
    public var platform: String
    public var bundlePath: String

    public init(id: String, name: String, platform: String, bundlePath: String) {
        self.id = id
        self.name = name
        self.platform = platform
        self.bundlePath = bundlePath
    }
}

public struct BuildConfiguration: Codable, Equatable {
    public var projectRoot: String
    public var swiftPackagePath: String
    public var executable: String
    public var configuration: String
    public var deployCommand: String

    public init(
        projectRoot: String,
        swiftPackagePath: String,
        executable: String,
        configuration: String,
        deployCommand: String
    ) {
        self.projectRoot = projectRoot
        self.swiftPackagePath = swiftPackagePath
        self.executable = executable
        self.configuration = configuration
        self.deployCommand = deployCommand
    }
}

public struct PackageDependency: Codable, Equatable {
    public var name: String
    public var path: String
    public var products: [String]

    public init(name: String, path: String, products: [String]) {
        self.name = name
        self.path = path
        self.products = products
    }
}

public struct ComponentUse: Codable, Equatable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct LocalModule: Codable, Equatable {
    public var name: String
    public var paths: [String]

    public init(name: String, paths: [String]) {
        self.name = name
        self.paths = paths
    }
}

public struct FingerprintConfiguration: Codable, Equatable {
    public var include: [String]
    public var exclude: [String]

    public init(include: [String], exclude: [String]) {
        self.include = include
        self.exclude = exclude
    }
}

public struct CustomCodePolicy: Codable, Equatable {
    public var allow: [String]

    public init(allow: [String]) {
        self.allow = allow
    }
}

public struct ComponentDefinition: Codable, Equatable {
    public var id: String
    public var purpose: String
    public var owner: String
    public var importName: String?
    public var docsPath: String
    public var integrationPoints: [String]
    public var duplicatePatterns: [String]

    public init(
        id: String,
        purpose: String,
        owner: String,
        importName: String?,
        docsPath: String,
        integrationPoints: [String],
        duplicatePatterns: [String]
    ) {
        self.id = id
        self.purpose = purpose
        self.owner = owner
        self.importName = importName
        self.docsPath = docsPath
        self.integrationPoints = integrationPoints
        self.duplicatePatterns = duplicatePatterns
    }
}

public enum BlueprintError: Error, CustomStringConvertible, Equatable {
    case parse(String)
    case validation(String)

    public var description: String {
        switch self {
        case .parse(let message):
            "Blueprint parse error: \(message)"
        case .validation(let message):
            "Blueprint validation error: \(message)"
        }
    }
}
