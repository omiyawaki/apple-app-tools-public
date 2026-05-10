import XCTest
@testable import AppleAppBlueprint
@testable import LocalAppUpdateKit

final class FingerprintAndGuardTests: XCTestCase {
    func testSourceFingerprintChangesWhenIncludedFileChanges() throws {
        let root = temporaryDirectory()
        try "one\n".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let config = FingerprintConfiguration(include: ["Package.swift"], exclude: [])

        let first = try SourceFingerprint.compute(projectRoot: root, configuration: config)
        try "two\n".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let second = try SourceFingerprint.compute(projectRoot: root, configuration: config)

        XCTAssertNotEqual(first.digest, second.digest)
    }

    func testDuplicateGuardBlocksHighConfidenceUpdaterDuplication() throws {
        let registry = ComponentRegistry.defaultRegistry()
        let blueprint = AppBlueprint(
            schemaVersion: 1,
            app: AppIdentity(id: "sample", name: "Sample", platform: "macOS", bundlePath: "~/Applications/Sample.app"),
            build: BuildConfiguration(projectRoot: "/tmp/sample", swiftPackagePath: ".", executable: "Sample", configuration: "debug", deployCommand: "./build-app.sh"),
            packageDependencies: [],
            components: [ComponentUse(id: "local-update-ui")],
            localModules: [],
            fingerprint: FingerprintConfiguration(include: ["Sources"], exclude: []),
            customCode: CustomCodePolicy(allow: ["Sources"])
        )
        let guardrail = UniversalComponentGuard(registry: registry)

        let result = guardrail.evaluate(
            blueprint: blueprint,
            path: "Sources/Sample/AppUpdater.swift",
            proposedContent: "struct AppUpdater { func redeployAndRelaunch() {} }"
        )

        XCTAssertEqual(result.severity, .block)
        XCTAssertEqual(result.componentID, "local-update-ui")
    }

    func testUpdateStateDetectsAvailableFingerprintDrift() {
        let metadata = LocalAppBuildMetadata(
            schemaVersion: 1,
            appID: "sample",
            projectRoot: "/tmp/sample",
            blueprintPath: "/tmp/sample/AppleAppBlueprint.yaml",
            bundlePath: "~/Applications/Sample.app",
            deployCommand: "./build-app.sh",
            sourceFingerprint: "old",
            gitHead: "abc",
            gitDirty: false,
            builtAt: "2026-05-07T00:00:00Z"
        )

        XCTAssertEqual(LocalAppUpdateStatus.compare(metadata: metadata, currentFingerprint: "new"), .updateAvailable)
        XCTAssertEqual(LocalAppUpdateStatus.compare(metadata: metadata, currentFingerprint: "old"), .upToDate)
    }

    func testUpdateDecisionRelaunchesWhenInstalledBundleIsNewerThanRunningApp() {
        let running = metadata(sourceFingerprint: "old", builtAt: "2026-05-08T12:00:00Z")
        let installed = metadata(sourceFingerprint: "new", builtAt: "2026-05-08T12:05:00Z")

        let decision = LocalAppUpdateDecision.evaluate(
            runningMetadata: running,
            installedMetadata: installed,
            currentSourceFingerprint: "new"
        )

        XCTAssertEqual(decision.status, .updateAvailable)
        XCTAssertEqual(decision.action, .relaunchInstalledBundle)
    }

    func testUpdateDecisionRelaunchesWhenInstalledBundleHasSameSourceButNewerBuild() {
        let running = metadata(sourceFingerprint: "same", builtAt: "2026-05-08T12:00:00Z")
        let installed = metadata(sourceFingerprint: "same", builtAt: "2026-05-08T12:05:00Z")

        let decision = LocalAppUpdateDecision.evaluate(
            runningMetadata: running,
            installedMetadata: installed,
            currentSourceFingerprint: "same"
        )

        XCTAssertEqual(decision.status, .updateAvailable)
        XCTAssertEqual(decision.action, .relaunchInstalledBundle)
    }

    func testUpdateDecisionDeploysWhenSourceIsNewerThanInstalledBundle() {
        let running = metadata(sourceFingerprint: "old", builtAt: "2026-05-08T12:00:00Z")
        let installed = metadata(sourceFingerprint: "new", builtAt: "2026-05-08T12:05:00Z")

        let decision = LocalAppUpdateDecision.evaluate(
            runningMetadata: running,
            installedMetadata: installed,
            currentSourceFingerprint: "newer-than-installed"
        )

        XCTAssertEqual(decision.status, .updateAvailable)
        XCTAssertEqual(decision.action, .deployAndRelaunch)
    }

    func testUpdateDecisionTreatsMatchingRunningAndInstalledMetadataAsCurrent() {
        let running = metadata(sourceFingerprint: "current", builtAt: "2026-05-08T12:00:00Z")
        let installed = metadata(sourceFingerprint: "current", builtAt: "2026-05-08T12:00:00Z")

        let decision = LocalAppUpdateDecision.evaluate(
            runningMetadata: running,
            installedMetadata: installed,
            currentSourceFingerprint: "current"
        )

        XCTAssertEqual(decision.status, .upToDate)
        XCTAssertNil(decision.action)
    }

    @MainActor
    func testUpdateControllerKeepsLaunchMetadataWhenBundleMetadataChangesOnDisk() async {
        let launched = metadata(sourceFingerprint: "old", builtAt: "2026-05-08T12:00:00Z")
        let overwritten = metadata(sourceFingerprint: "new", builtAt: "2026-05-08T12:05:00Z")
        var bundleMetadata = launched
        let controller = LocalAppUpdateController(
            runningMetadataLoader: { bundleMetadata },
            installedMetadataLoader: { _ in bundleMetadata },
            currentFingerprintLoader: { _ in "new" }
        )

        bundleMetadata = overwritten
        await controller.checkForUpdates()

        XCTAssertEqual(controller.status, .updateAvailable)
        XCTAssertEqual(controller.metadata, launched)
        XCTAssertEqual(controller.installedMetadata, overwritten)
    }

    private func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func metadata(sourceFingerprint: String, builtAt: String) -> LocalAppBuildMetadata {
        LocalAppBuildMetadata(
            schemaVersion: 1,
            appID: "sample",
            projectRoot: "/tmp/sample",
            blueprintPath: "/tmp/sample/AppleAppBlueprint.yaml",
            bundlePath: "~/Applications/Sample.app",
            deployCommand: "./build-app.sh",
            sourceFingerprint: sourceFingerprint,
            gitHead: "abc",
            gitDirty: false,
            builtAt: builtAt
        )
    }
}
