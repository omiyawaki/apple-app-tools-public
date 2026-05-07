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

    private func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
