import XCTest
@testable import AppleAppBlueprint

final class BlueprintTests: XCTestCase {
    func testBlueprintParsesAndValidatesKnownComponents() throws {
        let root = temporaryDirectory()
        let blueprintPath = root.appendingPathComponent("AppleAppBlueprint.yaml")
        try """
        schemaVersion: 1
        app:
          id: sample-mac
          name: Sample
          platform: macOS
          bundlePath: ~/Applications/Sample.app
        build:
          projectRoot: \(root.path)
          swiftPackagePath: .
          executable: SampleApp
          configuration: debug
          deployCommand: ./build-app.sh
        packageDependencies:
          - name: apple-app-tools
            path: /Users/example/tools/apple-app-tools
            products:
              - AppleAppDesignSystem
              - LocalAppUpdateKit
        components:
          - id: macos-design-system
          - id: local-update-ui
        localModules:
          - name: App Feature Code
            paths:
              - Sources/Sample
        fingerprint:
          include:
            - Package.swift
            - Sources
          exclude:
            - .build
        customCode:
          allow:
            - Sources/Sample
        """.write(to: blueprintPath, atomically: true, encoding: .utf8)

        let registry = ComponentRegistry.defaultRegistry()
        let blueprint = try AppBlueprint.load(from: blueprintPath)

        XCTAssertNoThrow(try BlueprintValidator(registry: registry).validate(blueprint))
        XCTAssertEqual(blueprint.app.id, "sample-mac")
        XCTAssertEqual(blueprint.components.map(\.id), ["macos-design-system", "local-update-ui"])
        XCTAssertEqual(blueprint.packageDependencies.first?.products, ["AppleAppDesignSystem", "LocalAppUpdateKit"])
    }

    func testBlueprintRejectsUnknownComponents() throws {
        let blueprint = AppBlueprint(
            schemaVersion: 1,
            app: AppIdentity(id: "sample", name: "Sample", platform: "macOS", bundlePath: "~/Applications/Sample.app"),
            build: BuildConfiguration(projectRoot: "/tmp/sample", swiftPackagePath: ".", executable: "Sample", configuration: "debug", deployCommand: "./build-app.sh"),
            packageDependencies: [],
            components: [ComponentUse(id: "not-real")],
            localModules: [],
            fingerprint: FingerprintConfiguration(include: ["Sources"], exclude: []),
            customCode: CustomCodePolicy(allow: ["Sources"])
        )

        XCTAssertThrowsError(try BlueprintValidator(registry: .defaultRegistry()).validate(blueprint)) { error in
            XCTAssertTrue(String(describing: error).contains("Unknown universal component"))
        }
    }

    func testRenderedMapIncludesUniversalComponentsAndLocalModules() throws {
        let blueprint = AppBlueprint(
            schemaVersion: 1,
            app: AppIdentity(id: "sample", name: "Sample", platform: "macOS", bundlePath: "~/Applications/Sample.app"),
            build: BuildConfiguration(projectRoot: "/tmp/sample", swiftPackagePath: ".", executable: "Sample", configuration: "debug", deployCommand: "./build-app.sh"),
            packageDependencies: [PackageDependency(name: "apple-app-tools", path: "/Users/example/tools/apple-app-tools", products: ["LocalAppUpdateKit"])],
            components: [ComponentUse(id: "local-update-ui")],
            localModules: [LocalModule(name: "Feature Code", paths: ["Sources/Sample"])],
            fingerprint: FingerprintConfiguration(include: ["Sources"], exclude: [".build"]),
            customCode: CustomCodePolicy(allow: ["Sources/Sample"])
        )

        let map = try AppMapRenderer(registry: .defaultRegistry()).render(blueprint)

        XCTAssertTrue(map.contains("# Sample App Map"))
        XCTAssertTrue(map.contains("local-update-ui"))
        XCTAssertTrue(map.contains("Feature Code"))
    }

    private func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
