import XCTest
@testable import AutoDeployCore

final class AutoDeployTests: XCTestCase {
    // MARK: VerifiedTag

    func testVerifiedTagFormatsCorrectly() {
        let tag = VerifiedTag(appID: "glean-mac", shortSHA: "abc1234")
        XCTAssertEqual(tag.name, "verified/glean-mac/abc1234")
        XCTAssertEqual(tag.refPattern, "verified/glean-mac/*")
    }

    func testVerifiedTagShortSHATrimsAndTruncates() {
        let short = VerifiedTag.shortSHA(from: "  deadbeefcafebabe1234567890abcdef00000000\n")
        XCTAssertEqual(short, "deadbee")
        XCTAssertEqual(short.count, 7)
    }

    func testVerifiedTagParsesShortAndFullForms() {
        let short = VerifiedTag.parse("verified/glean-mac/abc1234")
        XCTAssertEqual(short?.appID, "glean-mac")
        XCTAssertEqual(short?.shortSHA, "abc1234")

        let full = VerifiedTag.parse("refs/tags/verified/laps/0123abc")
        XCTAssertEqual(full?.appID, "laps")
        XCTAssertEqual(full?.shortSHA, "0123abc")
    }

    func testVerifiedTagRejectsMalformedRefs() {
        XCTAssertNil(VerifiedTag.parse(""))
        XCTAssertNil(VerifiedTag.parse("release/glean-mac/abc1234"))
        XCTAssertNil(VerifiedTag.parse("verified/glean-mac"))
        XCTAssertNil(VerifiedTag.parse("verified//abc1234"))
        XCTAssertNil(VerifiedTag.parse("verified/glean-mac/"))
    }

    func testVerifiedTagAppIDPatternEscapesIntoRefspace() {
        XCTAssertEqual(VerifiedTag.appIDPattern(for: "prospect-mac"), "refs/tags/verified/prospect-mac/*")
    }

    // MARK: NotifyPayload

    func testNotifyPayloadRoundTripsThroughJSON() throws {
        let payload = NotifyPayload(appID: "glean-mac", verifiedTag: "verified/glean-mac/abc1234")
        let data = try payload.encodeJSON()
        let decoded = try NotifyPayload.decodeJSON(data)
        XCTAssertEqual(decoded, payload)
    }

    func testNotifyPayloadUsesSnakeCaseKeys() throws {
        let payload = NotifyPayload(appID: "x", verifiedTag: "verified/x/1234567")
        let data = try payload.encodeJSON()
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"app_id\""), "expected snake_case app_id in \(json)")
        XCTAssertTrue(json.contains("\"verified_tag\""), "expected snake_case verified_tag in \(json)")
    }

    // MARK: HTTPRequestParser

    func testHTTPRequestParserExtractsMethodPathHeadersBody() throws {
        let raw = Data("""
        POST /notify HTTP/1.1\r
        Host: localhost:47681\r
        Content-Type: application/json\r
        Content-Length: 51\r
        \r
        {"app_id":"glean-mac","verified_tag":"verified/glean-mac/abc1234"}
        """.utf8)
        let parsed = try HTTPRequestParser.parse(raw)
        XCTAssertEqual(parsed.method, "POST")
        XCTAssertEqual(parsed.path, "/notify")
        XCTAssertEqual(parsed.headers["content-type"], "application/json")
        let body = try NotifyPayload.decodeJSON(parsed.body)
        XCTAssertEqual(body.appID, "glean-mac")
        XCTAssertEqual(body.verifiedTag, "verified/glean-mac/abc1234")
    }

    func testHTTPRequestParserRejectsMissingSeparator() {
        let raw = Data("POST /notify HTTP/1.1\r\nNo body separator here".utf8)
        XCTAssertThrowsError(try HTTPRequestParser.parse(raw))
    }

    // MARK: HTTPResponseBuilder

    func testHTTPResponseBuilderEmitsContentLengthAndStatusLine() {
        let data = HTTPResponseBuilder.plain(status: 200, reason: "OK", body: "ok: glean-mac\n")
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Length: 14\r\n"))
        XCTAssertTrue(text.hasSuffix("ok: glean-mac\n"))
    }

    // MARK: Registry

    func testRegistryDecodesSchema2EntriesWithTargetMachines() throws {
        let json = """
        {
          "schema": 2,
          "updated": "2026-05-16",
          "apps": [
            {
              "id": "glean-mac",
              "name": "Glean",
              "platform": "macOS",
              "scope": "universal",
              "status": "active",
              "source_path": "~/tools/glean-mac",
              "blueprint_path": "~/tools/glean-mac/AppleAppBlueprint.yaml",
              "deploy_command": "./build-app.sh",
              "bundle_path": "~/Applications/Glean.app",
              "required_tools": ["apple-app-tools"],
              "target_machines": ["host-a", "host-b", "host-c"],
              "smoke_seconds": 5
            }
          ]
        }
        """
        let url = try writeTemporaryRegistry(json: json)
        let registry = try PersonalAppRegistry.load(from: url)
        XCTAssertEqual(registry.schema, 2)
        XCTAssertEqual(registry.apps.count, 1)
        let app = try registry.app(id: "glean-mac")
        XCTAssertEqual(app.targetMachines, ["host-a", "host-b", "host-c"])
        XCTAssertEqual(app.smokeSecondsOrDefault(), 5)
    }

    func testRegistryHandlesSchema1EntriesWithoutTargetMachines() throws {
        let json = """
        {
          "schema": 1,
          "updated": "2026-05-15",
          "apps": [
            {
              "id": "legacy",
              "name": "Legacy",
              "platform": "macOS",
              "scope": "universal",
              "status": "active",
              "source_path": "~/tools/legacy",
              "blueprint_path": "~/tools/legacy/AppleAppBlueprint.yaml",
              "deploy_command": "./build-app.sh",
              "bundle_path": "~/Applications/Legacy.app",
              "required_tools": ["apple-app-tools"]
            }
          ]
        }
        """
        let url = try writeTemporaryRegistry(json: json)
        let registry = try PersonalAppRegistry.load(from: url)
        let app = try registry.app(id: "legacy")
        XCTAssertTrue(app.targetMachines.isEmpty)
        XCTAssertEqual(app.smokeSecondsOrDefault(), 3)
    }

    func testActiveAutoDeployAppsFiltersByStatusAndTargets() throws {
        let registry = PersonalAppRegistry(
            schema: 2,
            updated: "2026-05-16",
            apps: [
                PersonalApp(
                    id: "active-with-targets",
                    name: "A",
                    platform: "macOS",
                    scope: "universal",
                    status: "active",
                    sourcePath: "~/x",
                    blueprintPath: "~/x/B.yaml",
                    deployCommand: "./build-app.sh",
                    bundlePath: "~/Applications/A.app",
                    requiredTools: [],
                    targetMachines: ["host-a", "host-b"]
                ),
                PersonalApp(
                    id: "active-no-targets",
                    name: "B",
                    platform: "macOS",
                    scope: "universal",
                    status: "active",
                    sourcePath: "~/y",
                    blueprintPath: "~/y/B.yaml",
                    deployCommand: "./build-app.sh",
                    bundlePath: "~/Applications/B.app",
                    requiredTools: [],
                    targetMachines: []
                ),
                PersonalApp(
                    id: "retired",
                    name: "C",
                    platform: "macOS",
                    scope: "universal",
                    status: "retired",
                    sourcePath: "~/z",
                    blueprintPath: "~/z/B.yaml",
                    deployCommand: "./build-app.sh",
                    bundlePath: "~/Applications/C.app",
                    requiredTools: [],
                    targetMachines: ["host-a"]
                )
            ]
        )
        let active = registry.activeAutoDeployApps.map(\.id)
        XCTAssertEqual(active, ["active-with-targets"])
    }

    func testPeersExcludesLocalMachine() {
        let app = PersonalApp(
            id: "x",
            name: "X",
            platform: "macOS",
            scope: "universal",
            status: "active",
            sourcePath: "~/x",
            blueprintPath: "~/x/B.yaml",
            deployCommand: "./build-app.sh",
            bundlePath: "~/Applications/X.app",
            requiredTools: [],
            targetMachines: ["host-a", "host-b", "host-c"]
        )
        XCTAssertEqual(app.peers(excluding: "host-a"), ["host-b", "host-c"])
        XCTAssertEqual(app.peers(excluding: "absent"), ["host-a", "host-b", "host-c"])
    }

    func testRegistryLoadHonorsEnvironmentOverride() {
        let env = ["APPLE_APP_REGISTRY": "/tmp/custom-registry.json"]
        let url = PersonalAppRegistry.defaultRegistryURL(environment: env)
        XCTAssertEqual(url.path, "/tmp/custom-registry.json")
    }

    // MARK: CooldownStore

    func testCooldownStoreRecordsAndClears() throws {
        let temp = try makeTemporaryHome()
        let paths = DeployPaths(home: temp)
        let store = CooldownStore(paths: paths)

        XCTAssertNil(store.currentlySuppressedTag(forAppID: "glean-mac"))
        XCTAssertFalse(store.isSuppressed(appID: "glean-mac", tag: "verified/glean-mac/abc1234"))

        try store.recordFailure(appID: "glean-mac", tag: "verified/glean-mac/abc1234")
        XCTAssertEqual(store.currentlySuppressedTag(forAppID: "glean-mac"), "verified/glean-mac/abc1234")
        XCTAssertTrue(store.isSuppressed(appID: "glean-mac", tag: "verified/glean-mac/abc1234"))
        XCTAssertFalse(store.isSuppressed(appID: "glean-mac", tag: "verified/glean-mac/def5678"))

        store.clear(appID: "glean-mac")
        XCTAssertNil(store.currentlySuppressedTag(forAppID: "glean-mac"))
    }

    // MARK: helpers

    private func writeTemporaryRegistry(json: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-deploy-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("registry.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeTemporaryHome() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-deploy-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
