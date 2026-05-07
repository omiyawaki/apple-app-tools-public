import AppleAppBlueprint
import Foundation
import IconComposerBuild
import MacAppPackager

@main
struct AppleAppToolsCLI {
    static func main() {
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            guard let area = args.first else {
                throw CLIError("Usage: apple-app-tools blueprint|mac|icon ...")
            }
            args.removeFirst()
            switch area {
            case "blueprint":
                try runBlueprint(args)
            case "mac":
                try runMac(args)
            case "icon":
                CommandLineTool.main(arguments: args)
            default:
                throw CLIError("Unknown command area: \(area)")
            }
        } catch {
            FileHandle.standardError.writeLine("error: \(error)")
            exit(1)
        }
    }

    private static func runBlueprint(_ args: [String]) throws {
        guard let command = args.first else {
            throw CLIError("Usage: apple-app-tools blueprint validate|render-map|lock --config PATH")
        }
        let options = Options(Array(args.dropFirst()))
        let config = try options.required("--config")
        let blueprint = try AppBlueprint.load(from: URL(fileURLWithPath: config))
        let registry = ComponentRegistry.defaultRegistry()
        try BlueprintValidator(registry: registry).validate(blueprint)
        switch command {
        case "validate":
            print("valid")
        case "render-map":
            let output = try options.required("--out")
            let text = try AppMapRenderer(registry: registry).render(blueprint)
            try text.write(toFile: output, atomically: true, encoding: .utf8)
        case "lock":
            let output = try options.required("--out")
            let data = try JSONEncoder.pretty.encode(blueprint)
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        default:
            throw CLIError("Unknown blueprint command: \(command)")
        }
    }

    private static func runMac(_ args: [String]) throws {
        guard let command = args.first else {
            throw CLIError("Usage: apple-app-tools mac fingerprint|package ...")
        }
        let options = Options(Array(args.dropFirst()))
        let config = try options.required("--config")
        let blueprint = try AppBlueprint.load(from: URL(fileURLWithPath: config))
        try BlueprintValidator(registry: .defaultRegistry()).validate(blueprint)
        switch command {
        case "fingerprint":
            let root = URL(fileURLWithPath: NSString(string: blueprint.build.projectRoot).expandingTildeInPath)
            let fingerprint = try SourceFingerprint.compute(projectRoot: root, configuration: blueprint.fingerprint)
            print(fingerprint.digest)
        case "package":
            let binary = try options.required("--binary")
            let plist = try options.required("--plist")
            try MacAppPackager().package(
                options: MacPackageOptions(
                    blueprintPath: URL(fileURLWithPath: config),
                    binary: URL(fileURLWithPath: binary),
                    plist: URL(fileURLWithPath: plist),
                    resources: options.values("--resource").map { URL(fileURLWithPath: $0) }
                )
            )
        default:
            throw CLIError("Unknown mac command: \(command)")
        }
    }
}

private struct Options {
    var args: [String]

    init(_ args: [String]) {
        self.args = args
    }

    func required(_ key: String) throws -> String {
        guard let value = values(key).first else {
            throw CLIError("Missing required option \(key)")
        }
        return value
    }

    func values(_ key: String) -> [String] {
        var out: [String] = []
        var index = 0
        while index < args.count {
            if args[index] == key, index + 1 < args.count {
                out.append(args[index + 1])
                index += 2
            } else {
                index += 1
            }
        }
        return out
    }
}

private struct CLIError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

private extension FileHandle {
    func writeLine(_ string: String) {
        if let data = "\(string)\n".data(using: .utf8) {
            write(data)
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
