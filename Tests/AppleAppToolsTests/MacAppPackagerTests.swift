import XCTest
@testable import MacAppPackager

final class MacAppPackagerTests: XCTestCase {
    func testPackageRemovesStaleBundleRootContentsBeforeSigning() throws {
        let fixture = try makeFixture()
        let staleBundle = fixture.bundle.appendingPathComponent("Stale.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: staleBundle, withIntermediateDirectories: true)
        try "stale\n".write(to: staleBundle.appendingPathComponent("stale.txt"),
                            atomically: true,
                            encoding: .utf8)

        try withSigningIdentity("-") {
            try MacAppPackager().package(options: fixture.options)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleBundle.path))
    }

    func testPackageThrowsWhenCodesignFails() throws {
        let fixture = try makeFixture()

        try withSigningIdentity("Not A Real Signing Identity") {
            XCTAssertThrowsError(try MacAppPackager().package(options: fixture.options)) { error in
                let description = String(describing: error)
                XCTAssertTrue(description.contains("codesign"), description)
                XCTAssertTrue(description.contains("Not A Real Signing Identity"), description)
            }
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = temporaryDirectory()
        let bundle = root.appendingPathComponent("Sample.app", isDirectory: true)
        let blueprint = root.appendingPathComponent("AppleAppBlueprint.yaml")
        let binary = root.appendingPathComponent("Sample")
        let plist = root.appendingPathComponent("Info.plist")

        try "#!/bin/sh\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        try "fingerprint\n".write(to: root.appendingPathComponent("Package.swift"),
                                  atomically: true,
                                  encoding: .utf8)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>Sample</string>
            <key>CFBundleIdentifier</key>
            <string>com.example.sample</string>
            <key>CFBundleName</key>
            <string>Sample</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
        </dict>
        </plist>
        """.write(to: plist, atomically: true, encoding: .utf8)
        try """
        schemaVersion: 1
        app:
          id: sample
          name: Sample
          platform: macOS
          bundlePath: \(bundle.path)
        build:
          projectRoot: \(root.path)
          swiftPackagePath: .
          executable: Sample
          configuration: debug
          deployCommand: ./build-app.sh
        packageDependencies:
          - name: apple-app-tools
            path: /Users/example/tools/apple-app-tools
            products:
              - MacAppPackager
        components:
          - id: mac-app-packager
        localModules:
          - name: Sample
            paths:
              - Package.swift
        fingerprint:
          include:
            - Package.swift
          exclude:
            - .build
        customCode:
          allow:
            - Package.swift
        """.write(to: blueprint, atomically: true, encoding: .utf8)

        return Fixture(
            bundle: bundle,
            options: MacPackageOptions(
                blueprintPath: blueprint,
                binary: binary,
                plist: plist,
                resources: []
            )
        )
    }

    private func withSigningIdentity(_ identity: String, _ body: () throws -> Void) throws {
        let key = "APPLE_APP_SIGN_IDENTITY"
        let oldValue = getenv(key).map { String(cString: $0) }
        setenv(key, identity, 1)
        defer {
            if let oldValue {
                setenv(key, oldValue, 1)
            } else {
                unsetenv(key)
            }
        }
        try body()
    }

    private func temporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct Fixture {
        let bundle: URL
        let options: MacPackageOptions
    }
}
