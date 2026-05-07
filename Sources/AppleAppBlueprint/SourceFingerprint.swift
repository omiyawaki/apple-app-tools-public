import CryptoKit
import Foundation

public struct SourceFingerprint: Codable, Equatable {
    public var digest: String
    public var fileCount: Int

    public static func compute(projectRoot: URL, configuration: FingerprintConfiguration) throws -> SourceFingerprint {
        let root = projectRoot.standardizedFileURL
        let files = try includedFiles(root: root, configuration: configuration)
        var hasher = SHA256()
        for file in files {
            let rel = file.path.replacingOccurrences(of: root.path + "/", with: "")
            hasher.update(data: Data(rel.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: try Data(contentsOf: file))
            hasher.update(data: Data([0]))
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return SourceFingerprint(digest: digest, fileCount: files.count)
    }

    private static func includedFiles(root: URL, configuration: FingerprintConfiguration) throws -> [URL] {
        var out: [URL] = []
        for include in configuration.include {
            let url = root.appendingPathComponent(include)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if isDirectory(url) {
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                while let item = enumerator?.nextObject() as? URL {
                    if shouldExclude(item, root: root, excludes: configuration.exclude) {
                        if isDirectory(item) {
                            enumerator?.skipDescendants()
                        }
                        continue
                    }
                    if isRegularFile(item) {
                        out.append(item)
                    }
                }
            } else if isRegularFile(url), !shouldExclude(url, root: root, excludes: configuration.exclude) {
                out.append(url)
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    private static func shouldExclude(_ url: URL, root: URL, excludes: [String]) -> Bool {
        let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
        return excludes.contains { rel == $0 || rel.hasPrefix($0 + "/") }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
