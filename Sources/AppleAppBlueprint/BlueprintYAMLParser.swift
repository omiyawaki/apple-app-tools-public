import Foundation

public struct BlueprintYAMLParser {
    public init() {}

    public func parse(_ text: String) throws -> AppBlueprint {
        var parser = YAMLTreeParser(text: text)
        let root = try parser.parse()
        return AppBlueprint(
            schemaVersion: try root.int("schemaVersion"),
            app: AppIdentity(
                id: try root.map("app").string("id"),
                name: try root.map("app").string("name"),
                platform: try root.map("app").string("platform"),
                bundlePath: try root.map("app").string("bundlePath")
            ),
            build: BuildConfiguration(
                projectRoot: try root.map("build").string("projectRoot"),
                swiftPackagePath: try root.map("build").string("swiftPackagePath"),
                executable: try root.map("build").string("executable"),
                configuration: try root.map("build").string("configuration"),
                deployCommand: try root.map("build").string("deployCommand")
            ),
            packageDependencies: try root.array("packageDependencies").map { node in
                PackageDependency(
                    name: try node.string("name"),
                    path: try node.string("path"),
                    products: try node.stringArray("products")
                )
            },
            components: try root.array("components").map { node in
                ComponentUse(id: try node.string("id"))
            },
            localModules: try root.array("localModules").map { node in
                LocalModule(name: try node.string("name"), paths: try node.stringArray("paths"))
            },
            fingerprint: FingerprintConfiguration(
                include: try root.map("fingerprint").stringArray("include"),
                exclude: try root.map("fingerprint").stringArray("exclude")
            ),
            customCode: CustomCodePolicy(
                allow: try root.map("customCode").stringArray("allow")
            )
        )
    }
}

private enum YAMLNode: Equatable {
    case scalar(String)
    case mapping([String: YAMLNode])
    case array([YAMLNode])

    func string(_ key: String) throws -> String {
        guard case .mapping(let values) = self else {
            throw BlueprintError.parse("Expected mapping before reading \(key).")
        }
        guard case .scalar(let value) = values[key] else {
            throw BlueprintError.parse("Missing scalar key \(key).")
        }
        return value
    }

    func int(_ key: String) throws -> Int {
        let value = try string(key)
        guard let parsed = Int(value) else {
            throw BlueprintError.parse("Expected integer for \(key), got \(value).")
        }
        return parsed
    }

    func map(_ key: String) throws -> YAMLNode {
        guard case .mapping(let values) = self else {
            throw BlueprintError.parse("Expected mapping before reading \(key).")
        }
        guard let node = values[key], case .mapping = node else {
            throw BlueprintError.parse("Missing mapping key \(key).")
        }
        return node
    }

    func array(_ key: String) throws -> [YAMLNode] {
        guard case .mapping(let values) = self else {
            throw BlueprintError.parse("Expected mapping before reading \(key).")
        }
        guard let node = values[key], case .array(let array) = node else {
            throw BlueprintError.parse("Missing array key \(key).")
        }
        return array
    }

    func stringArray(_ key: String) throws -> [String] {
        try array(key).map { node in
            guard case .scalar(let value) = node else {
                throw BlueprintError.parse("Expected scalar item in \(key).")
            }
            return value
        }
    }
}

private struct YAMLLine {
    var indent: Int
    var text: String
}

private struct YAMLTreeParser {
    var lines: [YAMLLine]
    var index = 0

    init(text: String) {
        self.lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { raw in
                let noComment = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                let trimmed = noComment.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let indent = noComment.prefix { $0 == " " }.count
                return YAMLLine(indent: indent, text: String(trimmed))
            }
    }

    mutating func parse() throws -> YAMLNode {
        try parseMapping(indent: 0)
    }

    private mutating func parseMapping(indent: Int) throws -> YAMLNode {
        var values: [String: YAMLNode] = [:]
        while index < lines.count {
            let line = lines[index]
            if line.indent < indent { break }
            guard line.indent == indent else {
                throw BlueprintError.parse("Unexpected indentation near \(line.text).")
            }
            guard let colon = line.text.firstIndex(of: ":") else {
                throw BlueprintError.parse("Expected key-value line, got \(line.text).")
            }
            let key = String(line.text[..<colon]).trimmingCharacters(in: .whitespaces)
            let remainder = line.text[line.text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            index += 1
            if !remainder.isEmpty {
                values[key] = .scalar(stripQuotes(remainder))
            } else if index < lines.count && lines[index].indent > indent {
                values[key] = try parseNode(indent: lines[index].indent)
            } else {
                values[key] = .mapping([:])
            }
        }
        return .mapping(values)
    }

    private mutating func parseNode(indent: Int) throws -> YAMLNode {
        guard index < lines.count else {
            return .mapping([:])
        }
        if lines[index].text.hasPrefix("- ") {
            return try parseArray(indent: indent)
        }
        return try parseMapping(indent: indent)
    }

    private mutating func parseArray(indent: Int) throws -> YAMLNode {
        var values: [YAMLNode] = []
        while index < lines.count {
            let line = lines[index]
            if line.indent < indent { break }
            guard line.indent == indent, line.text.hasPrefix("- ") else { break }
            let itemText = String(line.text.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            index += 1
            if itemText.isEmpty {
                values.append(try parseNode(indent: indent + 2))
            } else if let colon = itemText.firstIndex(of: ":") {
                let key = String(itemText[..<colon]).trimmingCharacters(in: .whitespaces)
                let remainder = itemText[itemText.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                var map: [String: YAMLNode] = [:]
                map[key] = .scalar(stripQuotes(remainder))
                if index < lines.count && lines[index].indent > indent {
                    let nested = try parseMapping(indent: lines[index].indent)
                    if case .mapping(let nestedMap) = nested {
                        for (nestedKey, nestedValue) in nestedMap {
                            map[nestedKey] = nestedValue
                        }
                    }
                }
                values.append(.mapping(map))
            } else {
                values.append(.scalar(stripQuotes(itemText)))
            }
        }
        return .array(values)
    }

    private func stripQuotes(_ value: String) -> String {
        if value.count >= 2,
           (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
