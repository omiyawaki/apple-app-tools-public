import Foundation
import Combine

#if canImport(AppKit)
import AppKit
#endif

public struct LocalAppBuildMetadata: Codable, Equatable, Sendable {
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

    public static func loadFromAppBundle(path bundlePath: String) throws -> LocalAppBuildMetadata {
        let expandedPath = NSString(string: bundlePath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("LocalAppBuild.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LocalAppBuildMetadata.self, from: data)
    }
}

private extension LocalAppBuildMetadata {
    func isNewerThan(_ other: LocalAppBuildMetadata) -> Bool {
        guard let builtAtDate,
              let otherBuiltAtDate = other.builtAtDate else {
            return builtAt > other.builtAt
        }
        return builtAtDate > otherBuiltAtDate
    }

    private var builtAtDate: Date? {
        ISO8601DateFormatter().date(from: builtAt)
    }
}

private extension String {
    var lastNonEmptyLine: String {
        split(whereSeparator: \.isNewline)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

public enum LocalAppUpdateAction: Equatable {
    case deployAndRelaunch
    case relaunchInstalledBundle
}

public struct LocalAppUpdateDecision: Equatable {
    public var status: LocalAppUpdateStatus
    public var action: LocalAppUpdateAction?

    public static func evaluate(
        runningMetadata: LocalAppBuildMetadata,
        installedMetadata: LocalAppBuildMetadata?,
        currentSourceFingerprint: String
    ) -> LocalAppUpdateDecision {
        if let installedMetadata,
           installedMetadata.appID == runningMetadata.appID,
           installedMetadata.isNewerThan(runningMetadata),
           installedMetadata.sourceFingerprint == currentSourceFingerprint {
            return LocalAppUpdateDecision(status: .updateAvailable, action: .relaunchInstalledBundle)
        }

        if runningMetadata.sourceFingerprint != currentSourceFingerprint {
            return LocalAppUpdateDecision(status: .updateAvailable, action: .deployAndRelaunch)
        }

        if let installedMetadata,
           installedMetadata.appID == runningMetadata.appID,
           installedMetadata.isNewerThan(runningMetadata) {
            return LocalAppUpdateDecision(status: .updateAvailable, action: .relaunchInstalledBundle)
        }

        return LocalAppUpdateDecision(status: .upToDate, action: nil)
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
    @Published public private(set) var installedMetadata: LocalAppBuildMetadata?

    private let toolCommand: String
    private let runningMetadataResult: Result<LocalAppBuildMetadata, Error>
    private let installedMetadataLoader: (String) throws -> LocalAppBuildMetadata
    private let currentFingerprintLoader: ((LocalAppBuildMetadata) async throws -> String)?
    private var updateAction: LocalAppUpdateAction?
    private var monitorTask: Task<Void, Never>?

    public init(
        toolCommand: String = "/Users/example/tools/apple-app-tools/.build/release/apple-app-tools",
        runningMetadataLoader: () throws -> LocalAppBuildMetadata = {
            try LocalAppBuildMetadata.loadFromMainBundle()
        },
        installedMetadataLoader: @escaping (String) throws -> LocalAppBuildMetadata = {
            try LocalAppBuildMetadata.loadFromAppBundle(path: $0)
        },
        currentFingerprintLoader: ((LocalAppBuildMetadata) async throws -> String)? = nil
    ) {
        self.toolCommand = toolCommand
        self.runningMetadataResult = Result { try runningMetadataLoader() }
        self.installedMetadataLoader = installedMetadataLoader
        self.currentFingerprintLoader = currentFingerprintLoader
    }

    deinit {
        monitorTask?.cancel()
    }

    public var isUpdateVisible: Bool {
        if case .updateAvailable = status { return true }
        if case .updating = status { return true }
        if case .failed = status { return true }
        return false
    }

    public func checkForUpdates() async {
        await performUpdateCheck()
        startMonitoring()
    }

    public func startMonitoring(every seconds: TimeInterval = 30) {
        guard monitorTask == nil || monitorTask?.isCancelled == true else { return }
        let interval = UInt64(max(seconds, 1) * 1_000_000_000)
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performUpdateCheck()
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    return
                }
            }
        }
    }

    public func monitorForUpdates(every seconds: TimeInterval = 30) async {
        startMonitoring(every: seconds)
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 3_600_000_000_000)
            } catch {
                return
            }
        }
    }

    private func performUpdateCheck() async {
        if case .updating = status { return }
        status = .checking
        do {
            let loaded = try runningMetadataResult.get()
            metadata = loaded
            let installed = try? installedMetadataLoader(loaded.bundlePath)
            installedMetadata = installed
            let current = try await currentSourceFingerprint(for: loaded)
            let decision = LocalAppUpdateDecision.evaluate(
                runningMetadata: loaded,
                installedMetadata: installed,
                currentSourceFingerprint: current
            )
            updateAction = decision.action
            status = decision.status
        } catch LocalAppUpdateError.missingMetadata {
            updateAction = nil
            status = .upToDate
        } catch {
            updateAction = nil
            status = .failed(error.localizedDescription)
        }
    }

    private func currentSourceFingerprint(for metadata: LocalAppBuildMetadata) async throws -> String {
        if let currentFingerprintLoader {
            return try await currentFingerprintLoader(metadata)
        }
        return try await runTool(arguments: [
            "mac", "fingerprint",
            "--config", metadata.blueprintPath
        ]).lastNonEmptyLine
    }

    public func installUpdateAndRelaunch() {
        guard let metadata else {
            status = .failed("Update metadata is not loaded.")
            return
        }
        status = .updating
        let bundlePath = NSString(string: metadata.bundlePath).expandingTildeInPath
        let script: String
        switch updateAction {
        case .relaunchInstalledBundle:
            script = """
            sleep 0.3
            /usr/bin/open '\(bundlePath)'
            """
        case .deployAndRelaunch, nil:
            script = """
            sleep 0.3
            cd '\(metadata.projectRoot)'
            \(metadata.deployCommand)
            /usr/bin/open '\(bundlePath)'
            """
        }
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
