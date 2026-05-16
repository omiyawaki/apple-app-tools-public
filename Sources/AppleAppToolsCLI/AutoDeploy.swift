import AutoDeployCore
import Foundation
import LocalAppUpdateKit

enum AutoDeploy {
    static let listenerPort: Int = 47681

    static func run(_ args: [String]) throws {
        guard let command = args.first else {
            throw AutoDeployError(
                "Usage: apple-app-tools auto-deploy verify|notify|serve|catch-up|install-agents|uninstall-agents ..."
            )
        }
        let rest = Array(args.dropFirst())
        switch command {
        case "verify":
            try runVerify(rest)
        case "notify":
            try runNotify(rest)
        case "serve":
            try runServe(rest)
        case "catch-up":
            try runCatchUp(rest)
        case "install-agents":
            try runInstallAgents()
        case "uninstall-agents":
            try runUninstallAgents()
        default:
            throw AutoDeployError("Unknown auto-deploy command: \(command)")
        }
    }

    // MARK: verify

    static func runVerify(_ args: [String]) throws {
        let options = CLIOptions(args)
        let appID = try options.required("--app")
        let skipNotify = options.has("--no-notify")
        let registry = try PersonalAppRegistry.load()
        let app = try registry.app(id: appID)

        let head = try GitOps.revParseHead(at: app.expandedSourcePath)
        let short = VerifiedTag.shortSHA(from: head)
        let tag = VerifiedTag(appID: appID, shortSHA: short)

        let installed = try LocalAppBuildMetadata.loadFromAppBundle(path: app.bundlePath)
        if let installedHead = installed.gitHead, installedHead != head {
            throw AutoDeployError(
                "Installed bundle git_head \(installedHead) does not match source HEAD \(head). Rebuild first."
            )
        }

        try runSmokeCheck(for: app)

        let signed = supportsSignedTags()
        try GitOps.createTag(
            at: app.expandedSourcePath,
            name: tag.name,
            signed: signed,
            message: "Verified deploy of \(appID) on \(AutoDeployHelpers.localMachineName())"
        )
        try GitOps.pushTag(at: app.expandedSourcePath, name: tag.name)
        print("verified \(tag.name)")

        if !skipNotify {
            try runNotify(["--app", appID, "--tag", tag.name])
        }
    }

    static func runSmokeCheck(for app: PersonalApp) throws {
        if let custom = app.smokeCommand, !custom.isEmpty {
            let exe = custom[0]
            let args = Array(custom.dropFirst())
            let result = try AutoDeployHelpers.run(exe, args, timeoutSeconds: 60)
            guard result.succeeded else {
                throw AutoDeployError("smoke_command failed: \(result.stderr)")
            }
            return
        }
        let bundle = URL(fileURLWithPath: app.expandedBundlePath)
        let macOSDir = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: macOSDir.path),
              let binaryName = entries.first(where: { !$0.hasPrefix(".") }) else {
            throw AutoDeployError("Could not find executable inside \(macOSDir.path)")
        }
        let binary = macOSDir.appendingPathComponent(binaryName)
        let process = Process()
        process.executableURL = binary
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        let seconds = app.smokeSecondsOrDefault()
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            return
        }
        throw AutoDeployError("Smoke check failed: bundle exited within \(seconds)s with code \(process.terminationStatus)")
    }

    static func supportsSignedTags() -> Bool {
        let result = try? AutoDeployHelpers.run(
            GitOps.git,
            ["config", "--get", "user.signingkey"]
        )
        return result?.succeeded ?? false
    }

    // MARK: notify

    static func runNotify(_ args: [String]) throws {
        let options = CLIOptions(args)
        let appID = try options.required("--app")
        let tag = try options.required("--tag")
        let registry = try PersonalAppRegistry.load()
        let app = try registry.app(id: appID)
        let me = AutoDeployHelpers.localMachineName()
        let peers = app.peers(excluding: me)
        let payload = NotifyPayload(appID: appID, verifiedTag: tag)
        let payloadData = try payload.encodeJSON()
        for peer in peers {
            do {
                let ip = try TailscaleOps.ip4(forPeer: peer)
                try postNotify(toHost: ip, payload: payloadData)
                print("notified \(peer) (\(ip))")
            } catch {
                let message = "notify failed for \(peer): \(error)"
                FileHandle.standardError.write(Data((message + "\n").utf8))
                AutoDeployHelpers.appendLog(to: DeployPaths().autoDeployLog, message: message)
            }
        }
    }

    static func postNotify(toHost host: String, payload: Data) throws {
        guard let url = URL(string: "http://\(host):\(listenerPort)/notify") else {
            throw AutoDeployError("invalid listener URL for host \(host)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload
        request.timeoutInterval = 5

        final class Box: @unchecked Sendable {
            var status: Int = 0
            var error: Error?
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                box.error = error
            } else if let http = response as? HTTPURLResponse {
                box.status = http.statusCode
            }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 6)
        if let error = box.error { throw error }
        guard (200..<300).contains(box.status) else {
            throw AutoDeployError("notify peer returned HTTP \(box.status)")
        }
    }

    // MARK: serve

    static func runServe(_ args: [String] = []) throws {
        let options = CLIOptions(args)
        let bind = try options.required("--bind")
        let portString = try options.required("--port")
        guard let port = UInt16(portString) else {
            throw AutoDeployError("--port must be a 16-bit integer")
        }
        let listener = try SocketListener(bindAddress: bind, port: port)
        AutoDeployHelpers.appendLog(
            to: DeployPaths().autoDeployLog,
            message: "serve listening on \(bind):\(port)"
        )
        signal(SIGPIPE, SIG_IGN)
        while true {
            let connection: SocketListener.AcceptedConnection
            do {
                connection = try listener.accept()
            } catch {
                AutoDeployHelpers.appendLog(
                    to: DeployPaths().autoDeployLog,
                    message: "serve accept error: \(error)"
                )
                continue
            }
            defer { close(connection.fd) }
            do {
                let request = try connection.readAll(maxBytes: 64 * 1024)
                let response = handleServeRequest(rawRequest: request, peerAddress: connection.peerAddress)
                _ = try connection.writeAll(response)
            } catch {
                AutoDeployHelpers.appendLog(
                    to: DeployPaths().autoDeployLog,
                    message: "serve handler error from \(connection.peerAddress ?? "?"): \(error)"
                )
                let response = HTTPResponseBuilder.plain(status: 500, reason: "Internal Server Error", body: "\(error)\n")
                _ = try? connection.writeAll(response)
            }
        }
    }

    static func handleServeRequest(rawRequest: Data, peerAddress: String?) -> Data {
        do {
            let parsed = try HTTPRequestParser.parse(rawRequest)
            guard parsed.method == "POST" else {
                return HTTPResponseBuilder.plain(status: 405, reason: "Method Not Allowed", body: "method not allowed\n")
            }
            if let peerAddress, !TailscaleOps.whoisIsTailnet(remoteAddress: peerAddress) {
                AutoDeployHelpers.appendLog(
                    to: DeployPaths().autoDeployLog,
                    message: "serve rejected non-tailnet peer \(peerAddress)"
                )
                return HTTPResponseBuilder.plain(status: 403, reason: "Forbidden", body: "peer not in tailnet\n")
            }
            let payload = try NotifyPayload.decodeJSON(parsed.body)
            try runCatchUp(["--app", payload.appID])
            return HTTPResponseBuilder.plain(status: 200, reason: "OK", body: "ok: \(payload.appID)\n")
        } catch {
            AutoDeployHelpers.appendLog(
                to: DeployPaths().autoDeployLog,
                message: "serve error: \(error)"
            )
            return HTTPResponseBuilder.plain(status: 500, reason: "Internal Server Error", body: "\(error)\n")
        }
    }

    // MARK: catch-up

    static func runCatchUp(_ args: [String]) throws {
        let options = CLIOptions(args)
        let appFilter = options.optional("--app")
        let registry = try PersonalAppRegistry.load()
        let candidates = registry.activeAutoDeployApps.filter { appFilter == nil || $0.id == appFilter }
        if candidates.isEmpty {
            print("no apps to catch up")
            return
        }
        for app in candidates {
            do {
                try catchUpOne(app)
            } catch {
                let message = "catch-up failed for \(app.id): \(error)"
                FileHandle.standardError.write(Data((message + "\n").utf8))
                AutoDeployHelpers.appendLog(to: DeployPaths().autoDeployLog, message: message)
            }
        }
    }

    static func catchUpOne(_ app: PersonalApp) throws {
        let source = app.expandedSourcePath
        guard FileManager.default.fileExists(atPath: source) else {
            print("[\(app.id)] source path \(source) missing, skipping")
            return
        }
        let gitDir = URL(fileURLWithPath: source).appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: gitDir) else {
            print("[\(app.id)] source path \(source) is not a git repo, skipping")
            return
        }
        // Opt-in tag gate: apps that declare `require_signed_tags: true` in
        // the registry still pin auto-deploy to verified+signed tags. The
        // default (everything else) follows `origin`'s default branch — this
        // matches a solo push-to-main workflow and avoids the "I pushed an
        // hour ago, why is the other Mac still on yesterday's bundle" trap.
        let tagGated = app.requireSignedTags == true
        if tagGated {
            try catchUpFromTag(app, source: source)
        } else {
            try catchUpFromBranch(app, source: source)
        }
    }

    private static func catchUpFromTag(_ app: PersonalApp, source: String) throws {
        try GitOps.fetchTags(at: source)
        guard let tag = try GitOps.newestVerifiedTag(at: source, appID: app.id) else {
            print("[\(app.id)] no verified tag, skipping")
            return
        }
        let cooldown = CooldownStore()
        if cooldown.isSuppressed(appID: app.id, tag: tag.name) {
            print("[\(app.id)] tag \(tag.name) is in cooldown, skipping")
            return
        }
        let tagCommit = try GitOps.revParseTagCommit(at: source, tag: tag.name)
        let installed = try? LocalAppBuildMetadata.loadFromAppBundle(path: app.bundlePath)
        if let installedHead = installed?.gitHead, installedHead == tagCommit {
            print("[\(app.id)] already at \(tag.name)")
            return
        }
        if try !GitOps.verifyTagSignature(at: source, tag: tag.name) {
            throw AutoDeployError("tag \(tag.name) failed signature verification")
        }
        try deploy(app: app, source: source, ref: tag.name, label: tag.name, cooldown: cooldown)
    }

    private static func catchUpFromBranch(_ app: PersonalApp, source: String) throws {
        try GitOps.fetchOrigin(at: source)
        let target = try GitOps.revParseOriginDefault(at: source)
        let cooldown = CooldownStore()
        if cooldown.isSuppressed(appID: app.id, tag: target.commit) {
            print("[\(app.id)] \(target.ref)@\(target.commit) is in cooldown, skipping")
            return
        }
        let installed = try? LocalAppBuildMetadata.loadFromAppBundle(path: app.bundlePath)
        if let installedHead = installed?.gitHead, installedHead == target.commit {
            print("[\(app.id)] already at \(target.ref) (\(target.commit))")
            return
        }
        try deploy(
            app: app,
            source: source,
            ref: target.commit,
            label: "\(target.ref)@\(target.commit.prefix(8))",
            cooldown: cooldown
        )
    }

    private static func deploy(
        app: PersonalApp,
        source: String,
        ref: String,
        label: String,
        cooldown: CooldownStore
    ) throws {
        let paths = DeployPaths()
        let worktree = paths.deployCheckout(forAppID: app.id)
        try GitOps.ensureWorktree(at: worktree, sourcePath: source, ref: ref)
        let deployResult = try AutoDeployHelpers.run(
            "/bin/bash",
            ["-lc", app.deployCommand],
            cwd: worktree.path,
            captureOutput: true,
            timeoutSeconds: 600
        )
        if deployResult.succeeded {
            cooldown.clear(appID: app.id)
            AutoDeployHelpers.appendLog(
                to: paths.autoDeployLog,
                message: "deployed \(app.id) \(label) ok"
            )
            print("[\(app.id)] deployed \(label)")
        } else {
            try cooldown.recordFailure(appID: app.id, tag: ref)
            let lastErr = deployResult.stderr.split(whereSeparator: \.isNewline).suffix(200).joined(separator: "\n")
            AutoDeployHelpers.appendLog(
                to: paths.autoDeployLog,
                message: "deploy failed \(app.id) \(label) exit=\(deployResult.exitCode)\n\(lastErr)"
            )
            postUserNotification(title: "\(app.name) auto-deploy failed", body: label)
            throw AutoDeployError("deploy failed for \(app.id) at \(label) (exit \(deployResult.exitCode))")
        }
    }

    static func postUserNotification(title: String, body: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedBody = body.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedBody)\" with title \"\(escapedTitle)\""
        _ = try? AutoDeployHelpers.run("/usr/bin/osascript", ["-e", script], timeoutSeconds: 5)
    }

    // MARK: install / uninstall agents

    static func runInstallAgents() throws {
        let listenerIP = try TailscaleOps.ip4Self()
        let paths = DeployPaths()
        try AutoDeployHelpers.ensureDirectory(paths.launchAgentsRoot)
        try AutoDeployHelpers.ensureDirectory(paths.logsRoot)
        let toolPath = currentExecutablePath()

        let listenPlistName = "dev.aat.auto-deploy.listen.plist"
        let listenPlist = LaunchAgentTemplates.listenPlist(
            label: "dev.aat.auto-deploy.listen",
            toolPath: toolPath,
            bindAddress: listenerIP,
            port: listenerPort,
            logPath: paths.logsRoot.appendingPathComponent("listen.log").path
        )
        let listenPlistURL = paths.launchAgentsRoot.appendingPathComponent(listenPlistName)
        try listenPlist.write(to: listenPlistURL, atomically: true, encoding: .utf8)

        let catchUpPlistName = "dev.aat.auto-deploy.catch-up.plist"
        let catchUpPlist = LaunchAgentTemplates.catchUpPlist(
            label: "dev.aat.auto-deploy.catch-up",
            toolPath: toolPath,
            logPath: paths.logsRoot.appendingPathComponent("catch-up.log").path
        )
        let catchUpPlistURL = paths.launchAgentsRoot.appendingPathComponent(catchUpPlistName)
        try catchUpPlist.write(to: catchUpPlistURL, atomically: true, encoding: .utf8)

        let dailyPlistName = "dev.aat.auto-deploy.daily.plist"
        let dailyPlist = LaunchAgentTemplates.dailyPlist(
            label: "dev.aat.auto-deploy.daily",
            toolPath: toolPath,
            logPath: paths.logsRoot.appendingPathComponent("daily.log").path
        )
        let dailyPlistURL = paths.launchAgentsRoot.appendingPathComponent(dailyPlistName)
        try dailyPlist.write(to: dailyPlistURL, atomically: true, encoding: .utf8)

        let uid = String(getuid())
        for plist in [listenPlistURL, catchUpPlistURL, dailyPlistURL] {
            _ = try AutoDeployHelpers.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(plist.deletingPathExtension().lastPathComponent)"])
            let result = try AutoDeployHelpers.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist.path])
            if !result.succeeded {
                FileHandle.standardError.write(Data("warning: launchctl bootstrap \(plist.lastPathComponent) -> \(result.stderr)\n".utf8))
            }
        }
        print("installed agents bound to \(listenerIP):\(listenerPort)")
    }

    static func runUninstallAgents() throws {
        let paths = DeployPaths()
        let uid = String(getuid())
        let names = ["dev.aat.auto-deploy.listen", "dev.aat.auto-deploy.catch-up", "dev.aat.auto-deploy.daily"]
        for name in names {
            _ = try AutoDeployHelpers.run("/bin/launchctl", ["bootout", "gui/\(uid)/\(name)"])
            let url = paths.launchAgentsRoot.appendingPathComponent("\(name).plist")
            try? FileManager.default.removeItem(at: url)
        }
        print("uninstalled agents")
    }

    static func currentExecutablePath() -> String {
        var pathBuffer = [UInt8](repeating: 0, count: 4096)
        var size = UInt32(pathBuffer.count)
        let result = pathBuffer.withUnsafeMutableBufferPointer { buf -> Int32 in
            buf.baseAddress.map { ptr in
                _NSGetExecutablePath(UnsafeMutablePointer<CChar>(OpaquePointer(ptr)), &size)
            } ?? -1
        }
        if result == 0 {
            let nullTerminated = pathBuffer.prefix(while: { $0 != 0 })
            return String(decoding: nullTerminated, as: UTF8.self)
        }
        return "/usr/local/bin/apple-app-tools"
    }
}

struct AutoDeployError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

struct CLIOptions {
    var args: [String]

    init(_ args: [String]) {
        self.args = args
    }

    func required(_ key: String) throws -> String {
        guard let value = optional(key) else {
            throw AutoDeployError("Missing required option \(key)")
        }
        return value
    }

    func optional(_ key: String) -> String? {
        var index = 0
        while index < args.count {
            if args[index] == key, index + 1 < args.count {
                return args[index + 1]
            }
            index += 1
        }
        return nil
    }

    func has(_ key: String) -> Bool {
        args.contains(key)
    }
}
