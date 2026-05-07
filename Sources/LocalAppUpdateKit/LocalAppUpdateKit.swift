import Foundation
import Combine

#if canImport(AppKit)
import AppKit
#endif

public struct LocalAppBuildMetadata: Codable, Equatable {
    public var schemaVersion: Int
    public var appID: String
    public var projectRoot: String
    public var blueprintPath: String
    public var bundlePath: String
    public var deployCommand: String
    public var sourceFingerprint: String
    public var gitHead: String?
    public var gitDirty: Bool
    public var builtAt: String

    public init(
        schemaVersion: Int,
        appID: String,
        projectRoot: String,
        blueprintPath: String,
        bundlePath: String,
        deployCommand: String,
        sourceFingerprint: String,
        gitHead: String?,
        gitDirty: Bool,
        builtAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.appID = appID
        self.projectRoot = projectRoot
        self.blueprintPath = blueprintPath
        self.bundlePath = bundlePath
        self.deployCommand = deployCommand
        self.sourceFingerprint = sourceFingerprint
        self.gitHead = gitHead
        self.gitDirty = gitDirty
        self.builtAt = builtAt
    }

    public static func loadFromMainBundle() throws -> LocalAppBuildMetadata {
        guard let url = Bundle.main.url(forResource: "LocalAppBuild", withExtension: "json") else {
            throw LocalAppUpdateError.missingMetadata
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LocalAppBuildMetadata.self, from: data)
    }
}

public enum LocalAppUpdateStatus: Equatable {
    case unknown
    case checking
    case upToDate
    case updateAvailable
    case updating
    case failed(String)

    public static func compare(metadata: LocalAppBuildMetadata, currentFingerprint: String) -> LocalAppUpdateStatus {
        metadata.sourceFingerprint == currentFingerprint ? .upToDate : .updateAvailable
    }
}

public enum LocalAppUpdateError: Error, LocalizedError {
    case missingMetadata
    case toolFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingMetadata:
            "LocalAppBuild.json was not found in the app bundle."
        case .toolFailed(let message):
            message
        }
    }
}

@MainActor
public final class LocalAppUpdateController: ObservableObject {
    @Published public private(set) var status: LocalAppUpdateStatus = .unknown
    @Published public private(set) var metadata: LocalAppBuildMetadata?

    private let toolCommand: String

    public init(toolCommand: String = "/Users/example/tools/apple-app-tools/.build/release/apple-app-tools") {
        self.toolCommand = toolCommand
    }

    public var isUpdateVisible: Bool {
        if case .updateAvailable = status { return true }
        if case .updating = status { return true }
        if case .failed = status { return true }
        return false
    }

    public func checkForUpdates() async {
        status = .checking
        do {
            let loaded = try LocalAppBuildMetadata.loadFromMainBundle()
            metadata = loaded
            let current = try await runTool(arguments: [
                "mac", "fingerprint",
                "--config", loaded.blueprintPath
            ])
            status = LocalAppUpdateStatus.compare(
                metadata: loaded,
                currentFingerprint: current.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch LocalAppUpdateError.missingMetadata {
            status = .upToDate
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    public func installUpdateAndRelaunch() {
        guard let metadata else {
            status = .failed("Update metadata is not loaded.")
            return
        }
        status = .updating
        let script = """
        sleep 0.3
        cd '\(metadata.projectRoot)'
        \(metadata.deployCommand)
        /usr/bin/open '\(NSString(string: metadata.bundlePath).expandingTildeInPath)'
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", script]
        do {
            try process.run()
            #if canImport(AppKit)
            NSApp.terminate(nil)
            #endif
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private nonisolated func runTool(arguments: [String]) async throws -> String {
        let command = toolCommand
        return try await Task.detached {
            let executable = FileManager.default.fileExists(atPath: command)
                ? command
                : "/usr/bin/env"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = executable == "/usr/bin/env"
                ? ["swift", "run", "--package-path", "/Users/example/tools/apple-app-tools", "-c", "release", "apple-app-tools"] + arguments
                : arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw LocalAppUpdateError.toolFailed(output)
            }
            return output
        }.value
    }
}
