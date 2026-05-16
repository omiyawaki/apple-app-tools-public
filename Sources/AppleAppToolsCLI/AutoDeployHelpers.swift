import AutoDeployCore
import Foundation

enum AutoDeployHelpers {
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: String? = nil,
        env: [String: String]? = nil,
        captureOutput: Bool = true,
        timeoutSeconds: TimeInterval? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: NSString(string: cwd).expandingTildeInPath)
        }
        if let env {
            process.environment = env
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        if captureOutput {
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
        }
        try process.run()
        if let timeoutSeconds {
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                return ProcessResult(exitCode: -1, stdout: "", stderr: "timeout after \(timeoutSeconds)s")
            }
        } else {
            process.waitUntilExit()
        }
        let stdout = captureOutput
            ? (String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            : ""
        let stderr = captureOutput
            ? (String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            : ""
        return ProcessResult(exitCode: Int(process.terminationStatus), stdout: stdout, stderr: stderr)
    }

    static func localMachineName() -> String {
        if let override = ProcessInfo.processInfo.environment["APPLE_APP_LOCAL_MACHINE"], !override.isEmpty {
            return override
        }
        var buffer = [UInt8](repeating: 0, count: 256)
        let success = buffer.withUnsafeMutableBufferPointer { buf -> Bool in
            buf.baseAddress.map { ptr in
                gethostname(UnsafeMutablePointer<CChar>(OpaquePointer(ptr)), buf.count) == 0
            } ?? false
        }
        if success {
            let nullTerminated = buffer.prefix(while: { $0 != 0 })
            let raw = String(decoding: nullTerminated, as: UTF8.self)
            return raw.split(separator: ".").first.map(String.init) ?? raw
        }
        return Host.current().localizedName ?? "unknown"
    }

    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func appendLog(to url: URL, message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            FileHandle.standardError.write(Data("warning: failed to write log line: \(error)\n".utf8))
        }
    }
}

struct ProcessResult {
    var exitCode: Int
    var stdout: String
    var stderr: String

    var succeeded: Bool { exitCode == 0 }

    var trimmedStdout: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GitOps {
    static let git = "/usr/bin/git"

    static func revParseHead(at sourcePath: String) throws -> String {
        let result = try AutoDeployHelpers.run(git, ["rev-parse", "HEAD"], cwd: sourcePath)
        guard result.succeeded else {
            throw GitError.commandFailed("rev-parse HEAD", result.stderr)
        }
        return result.trimmedStdout
    }

    static func revParseTagCommit(at sourcePath: String, tag: String) throws -> String {
        let result = try AutoDeployHelpers.run(git, ["rev-list", "-n", "1", tag], cwd: sourcePath)
        guard result.succeeded else {
            throw GitError.commandFailed("rev-list -n 1 \(tag)", result.stderr)
        }
        return result.trimmedStdout
    }

    static func fetchTags(at sourcePath: String) throws {
        let result = try AutoDeployHelpers.run(git, ["fetch", "--tags", "--quiet"], cwd: sourcePath)
        guard result.succeeded else {
            throw GitError.commandFailed("fetch --tags", result.stderr)
        }
    }

    static func fetchOrigin(at sourcePath: String) throws {
        let result = try AutoDeployHelpers.run(git, ["fetch", "--quiet", "origin"], cwd: sourcePath)
        guard result.succeeded else {
            throw GitError.commandFailed("fetch origin", result.stderr)
        }
    }

    /// Resolve the default branch on `origin` (whichever of main/master is
    /// the symbolic-ref target). Falls back to `origin/main` then
    /// `origin/master` if the symbolic ref isn't set locally.
    static func revParseOriginDefault(at sourcePath: String) throws -> (ref: String, commit: String) {
        let sym = try AutoDeployHelpers.run(
            git,
            ["symbolic-ref", "-q", "refs/remotes/origin/HEAD"],
            cwd: sourcePath
        )
        let ref: String
        if sym.succeeded, !sym.trimmedStdout.isEmpty {
            let full = sym.trimmedStdout
            ref = full.hasPrefix("refs/remotes/")
                ? String(full.dropFirst("refs/remotes/".count))
                : full
        } else {
            let main = try AutoDeployHelpers.run(git, ["rev-parse", "--verify", "-q", "origin/main"], cwd: sourcePath)
            if main.succeeded {
                ref = "origin/main"
            } else {
                let master = try AutoDeployHelpers.run(git, ["rev-parse", "--verify", "-q", "origin/master"], cwd: sourcePath)
                guard master.succeeded else {
                    throw GitError.commandFailed("resolve origin/HEAD", "no origin/main or origin/master")
                }
                ref = "origin/master"
            }
        }
        let commit = try AutoDeployHelpers.run(git, ["rev-parse", ref], cwd: sourcePath)
        guard commit.succeeded else {
            throw GitError.commandFailed("rev-parse \(ref)", commit.stderr)
        }
        return (ref, commit.trimmedStdout)
    }

    static func newestVerifiedTag(at sourcePath: String, appID: String) throws -> VerifiedTag? {
        let pattern = VerifiedTag.appIDPattern(for: appID)
        let result = try AutoDeployHelpers.run(
            git,
            ["for-each-ref", "--sort=-creatordate", "--count=1", "--format=%(refname:short)", pattern],
            cwd: sourcePath
        )
        guard result.succeeded else {
            throw GitError.commandFailed("for-each-ref \(pattern)", result.stderr)
        }
        let name = result.trimmedStdout
        guard !name.isEmpty else { return nil }
        return VerifiedTag.parse(name)
    }

    static func createTag(at sourcePath: String, name: String, signed: Bool, message: String) throws {
        let args = signed
            ? ["tag", "-s", name, "-m", message]
            : ["tag", "-a", name, "-m", message]
        let result = try AutoDeployHelpers.run(git, args, cwd: sourcePath)
        guard result.succeeded else {
            throw GitError.commandFailed("tag \(name)", result.stderr)
        }
    }

    static func pushTag(at sourcePath: String, name: String) throws {
        let result = try AutoDeployHelpers.run(git, ["push", "origin", "refs/tags/\(name)"], cwd: sourcePath)
        guard result.succeeded else {
            throw GitError.commandFailed("push tag \(name)", result.stderr)
        }
    }

    static func ensureWorktree(at worktreePath: URL, sourcePath: String, ref: String) throws {
        if !FileManager.default.fileExists(atPath: worktreePath.path) {
            try AutoDeployHelpers.ensureDirectory(worktreePath.deletingLastPathComponent())
            let result = try AutoDeployHelpers.run(
                git,
                ["worktree", "add", "--detach", worktreePath.path, ref],
                cwd: sourcePath
            )
            guard result.succeeded else {
                throw GitError.commandFailed("worktree add \(worktreePath.path)", result.stderr)
            }
            return
        }
        let result = try AutoDeployHelpers.run(git, ["checkout", "--detach", ref], cwd: worktreePath.path)
        guard result.succeeded else {
            throw GitError.commandFailed("checkout \(ref) in worktree", result.stderr)
        }
    }

    static func verifyTagSignature(at sourcePath: String, tag: String) throws -> Bool {
        let result = try AutoDeployHelpers.run(git, ["tag", "-v", tag], cwd: sourcePath)
        return result.succeeded
    }
}

enum GitError: Error, CustomStringConvertible {
    case commandFailed(String, String)

    var description: String {
        switch self {
        case .commandFailed(let cmd, let stderr):
            "git \(cmd) failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

enum TailscaleOps {
    // The Tailscale.app bundle ships two argv[0]-dispatched modes from the same
    // inode: "Tailscale" boots the GUI helper and fails under a minimal launchd
    // env, "tailscale" is the standalone CLI that talks to tailscaled directly.
    // Even with the lowercase path, the CLI binary's mode-detection fails when
    // execed directly under a minimal env (parent process group, controlling
    // context, or similar). Invoking through /bin/sh -c reliably puts it in
    // CLI mode regardless of caller env. Prefer /usr/local/bin/tailscale when
    // present (already a sh-wrapper), otherwise wrap the lowercase path here.
    static let tailscaleWrapper = "/usr/local/bin/tailscale"
    static let tailscaleLowercase = "/Applications/Tailscale.app/Contents/MacOS/tailscale"

    static func runTailscale(_ args: [String], timeoutSeconds: TimeInterval = 5) throws -> ProcessResult {
        let executable: String
        if FileManager.default.isExecutableFile(atPath: tailscaleWrapper) {
            executable = tailscaleWrapper
        } else {
            executable = tailscaleLowercase
        }
        let quoted = ([executable] + args).map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: " ")
        return try AutoDeployHelpers.run("/bin/sh", ["-c", quoted], timeoutSeconds: timeoutSeconds)
    }

    static func ip4(forPeer name: String) throws -> String {
        let result = try runTailscale(["ip", "-4", name])
        guard result.succeeded else {
            throw TailscaleError.commandFailed("ip -4 \(name)", result.stderr)
        }
        let first = result.stdout
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        guard !first.isEmpty else {
            throw TailscaleError.commandFailed("ip -4 \(name)", "empty output")
        }
        return first
    }

    static func ip4Self() throws -> String {
        let result = try runTailscale(["ip", "-4"])
        guard result.succeeded else {
            throw TailscaleError.commandFailed("ip -4", result.stderr)
        }
        let first = result.stdout
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        guard !first.isEmpty else {
            throw TailscaleError.commandFailed("ip -4", "empty output")
        }
        return first
    }

    static func whoisIsTailnet(remoteAddress: String) -> Bool {
        let host = remoteAddress.split(separator: ":").first.map(String.init) ?? remoteAddress
        guard let result = try? runTailscale(["whois", host]) else {
            return false
        }
        return result.succeeded && result.stdout.contains("Machine:")
    }
}

enum TailscaleError: Error, CustomStringConvertible {
    case commandFailed(String, String)

    var description: String {
        switch self {
        case .commandFailed(let cmd, let stderr):
            "tailscale \(cmd) failed: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}
