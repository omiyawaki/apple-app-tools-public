import Foundation

public enum ToolLocator {
    public static func resolveICTool(explicit: URL?) throws -> URL {
        if let explicit {
            return try requireExecutable(explicit, name: "ictool")
        }

        if let env = ProcessInfo.processInfo.environment["ICTOOL"], !env.isEmpty {
            return try requireExecutable(URL(fileURLWithPath: env), name: "ictool")
        }

        let candidates = try ictoolCandidates()
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw BuildError("Icon Composer ictool was not found. Set ICTOOL or pass --ictool.")
    }

    public static func resolveXcrunTool(_ name: String) throws -> URL {
        let output = try runAndCapture(URL(fileURLWithPath: "/usr/bin/xcrun"), ["--find", name])
        return try requireExecutable(URL(fileURLWithPath: output), name: name)
    }

    private static func ictoolCandidates() throws -> [URL] {
        var candidates = [
            URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool")
        ]

        if let developerDir = try? runAndCapture(URL(fileURLWithPath: "/usr/bin/xcode-select"), ["-p"]) {
            let developer = URL(fileURLWithPath: developerDir)
            let xcodeApp = developer.deletingLastPathComponent().deletingLastPathComponent()
            candidates.insert(
                xcodeApp.appendingPathComponent("Contents/Applications/Icon Composer.app/Contents/Executables/ictool"),
                at: 0
            )
        }

        return candidates
    }

    private static func requireExecutable(_ url: URL, name: String) throws -> URL {
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw BuildError("\(name) is not executable at \(url.path)")
        }
        return url
    }

    private static func runAndCapture(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? ""
            throw BuildError("\(executable.lastPathComponent) failed: \(message)")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
