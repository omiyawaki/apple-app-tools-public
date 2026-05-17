import AppleAppBlueprint
import Foundation

public struct MacPackageOptions {
    public var blueprintPath: URL
    public var binary: URL
    public var plist: URL
    public var resources: [URL]
    /// Optional override for `blueprint.app.bundlePath`. Use when producing
    /// a sibling-variant bundle (e.g. a headless companion at a different
    /// path) from the same blueprint.
    public var bundlePathOverride: URL?

    public init(blueprintPath: URL, binary: URL, plist: URL, resources: [URL], bundlePathOverride: URL? = nil) {
        self.blueprintPath = blueprintPath
        self.binary = binary
        self.plist = plist
        self.resources = resources
        self.bundlePathOverride = bundlePathOverride
    }
}

public struct MacAppPackager {
    public init() {}

    public func package(options: MacPackageOptions) throws {
        let blueprint = try AppBlueprint.load(from: options.blueprintPath)
        try BlueprintValidator(registry: .defaultRegistry()).validate(blueprint)
        let bundle = options.bundlePathOverride
            ?? URL(fileURLWithPath: NSString(string: blueprint.app.bundlePath).expandingTildeInPath)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let macOS = contents.appendingPathComponent("MacOS", isDirectory: true)
        let resources = contents.appendingPathComponent("Resources", isDirectory: true)

        if FileManager.default.fileExists(atPath: contents.path) {
            try FileManager.default.removeItem(at: contents)
        }
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

        let executable = blueprint.build.executable
        try copyReplacing(options.binary, to: macOS.appendingPathComponent(executable))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macOS.appendingPathComponent(executable).path)
        try copyReplacing(options.plist, to: contents.appendingPathComponent("Info.plist"))

        for resource in options.resources where FileManager.default.fileExists(atPath: resource.path) {
            try copyReplacing(resource, to: resources.appendingPathComponent(resource.lastPathComponent))
        }

        let metadata = try buildMetadata(blueprint: blueprint, blueprintPath: options.blueprintPath)
        let data = try JSONEncoder.pretty.encode(metadata)
        try data.write(to: resources.appendingPathComponent("LocalAppBuild.json"), options: .atomic)
        sign(bundle: bundle)
        register(bundle: bundle)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: bundle.path)
    }

    private func buildMetadata(blueprint: AppBlueprint, blueprintPath: URL) throws -> [String: AnyCodable] {
        let root = URL(fileURLWithPath: NSString(string: blueprint.build.projectRoot).expandingTildeInPath)
        let fingerprint = try SourceFingerprint.compute(projectRoot: root, configuration: blueprint.fingerprint)
        return [
            "schemaVersion": AnyCodable(1),
            "appID": AnyCodable(blueprint.app.id),
            "projectRoot": AnyCodable(root.path),
            "blueprintPath": AnyCodable(blueprintPath.path),
            "bundlePath": AnyCodable(blueprint.app.bundlePath),
            "deployCommand": AnyCodable(blueprint.build.deployCommand),
            "sourceFingerprint": AnyCodable(fingerprint.digest),
            "gitHead": AnyCodable(git(root: root, arguments: ["rev-parse", "HEAD"])),
            "gitDirty": AnyCodable(!(git(root: root, arguments: ["status", "--porcelain"]) ?? "").isEmpty),
            "builtAt": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]
    }

    private func copyReplacing(_ source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func sign(bundle: URL) {
        // Resolution order:
        //   1. APPLE_APP_SIGN_IDENTITY env var (explicit override)
        //   2. The first installed code-signing identity, preferring
        //      Developer ID Application > Apple Development > Mac Developer.
        //   3. Ad-hoc ("-") only if no identity is available.
        //
        // Stable signing matters because macOS keychain ACLs (e.g. the
        // "<App> WebCrypto Master Key" item WKWebView creates) are bound
        // to the app's signing identity. Ad-hoc signing keys those ACLs
        // to the per-binary cdhash, which changes on every rebuild, so
        // the user gets prompted for keychain access after every
        // `./build-app.sh`. With a real (Apple Development or Developer
        // ID) cert the signing identity is stable across rebuilds and
        // the "Always Allow" decision sticks.
        let identity = signingIdentity()
        let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
        if identity == "-" {
            FileHandle.standardError.write(Data(
                "warning: no code-signing identity found, falling back to ad-hoc; keychain prompts will repeat on every rebuild\n".utf8))
            _ = run(codesign, ["--force", "--deep", "--sign", "-", bundle.path])
        } else {
            FileHandle.standardError.write(Data(
                "codesign: \(identity)\n".utf8))
            _ = run(codesign, ["--force", "--deep", "--options", "runtime", "--sign", identity, bundle.path])
        }
    }

    private func signingIdentity() -> String {
        let env = ProcessInfo.processInfo.environment["APPLE_APP_SIGN_IDENTITY"] ?? ""
        if !env.isEmpty { return env }

        // `security find-identity -v -p codesigning` prints lines like:
        //   1) ABCDEF... "Apple Development: Name (TEAMID)"
        // Newest-first; we pick the most-trusted match. Quoted SHA + name.
        let output = run(
            URL(fileURLWithPath: "/usr/bin/security"),
            ["find-identity", "-v", "-p", "codesigning"]
        ) ?? ""
        let candidates: [String] = output
            .split(separator: "\n")
            .compactMap { line in
                guard let firstQuote = line.firstIndex(of: "\""),
                      let lastQuote = line.lastIndex(of: "\""),
                      firstQuote != lastQuote
                else { return nil }
                let name = line[line.index(after: firstQuote)..<lastQuote]
                return String(name)
            }
        let priorities: [String] = [
            "Developer ID Application",
            "Apple Development",
            "Mac Developer",
        ]
        for prefix in priorities {
            if let hit = candidates.first(where: { $0.hasPrefix(prefix) }) {
                return hit
            }
        }
        if let any = candidates.first { return any }
        return "-"
    }

    private func register(bundle: URL) {
        let lsregister = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        guard FileManager.default.fileExists(atPath: lsregister.path) else { return }
        _ = run(lsregister, ["-f", bundle.path])
    }

    private func git(root: URL, arguments: [String]) -> String? {
        run(URL(fileURLWithPath: "/usr/bin/git"), ["-C", root.path] + arguments)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ executable: URL, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

private struct AnyCodable: Encodable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let value as String:
            try container.encode(value)
        case let value as Int:
            try container.encode(value)
        case let value as Bool:
            try container.encode(value)
        case nil:
            try container.encodeNil()
        default:
            try container.encode(String(describing: value))
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
