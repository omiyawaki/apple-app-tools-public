import Foundation

public struct NotifyPayload: Codable, Equatable, Sendable {
    public var appID: String
    public var verifiedTag: String

    public init(appID: String, verifiedTag: String) {
        self.appID = appID
        self.verifiedTag = verifiedTag
    }

    enum CodingKeys: String, CodingKey {
        case appID = "app_id"
        case verifiedTag = "verified_tag"
    }

    public func encodeJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decodeJSON(_ data: Data) throws -> NotifyPayload {
        try JSONDecoder().decode(NotifyPayload.self, from: data)
    }
}

public struct HTTPRequestParser {
    public struct Parsed: Equatable {
        public var method: String
        public var path: String
        public var headers: [String: String]
        public var body: Data
    }

    public static func parse(_ raw: Data) throws -> Parsed {
        guard let separatorRange = raw.range(of: Data("\r\n\r\n".utf8)) else {
            throw HTTPParseError.malformed("Missing header/body separator")
        }
        let headerPart = raw.subdata(in: 0..<separatorRange.lowerBound)
        let body = raw.subdata(in: separatorRange.upperBound..<raw.count)
        guard let headerText = String(data: headerPart, encoding: .utf8) else {
            throw HTTPParseError.malformed("Headers are not UTF-8")
        }
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let requestLine = lines.first else {
            throw HTTPParseError.malformed("Empty request")
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard requestParts.count >= 2 else {
            throw HTTPParseError.malformed("Bad request line")
        }
        let method = requestParts[0]
        let path = requestParts[1]
        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        return Parsed(method: method, path: path, headers: headers, body: body)
    }
}

public enum HTTPParseError: Error, CustomStringConvertible {
    case malformed(String)

    public var description: String {
        switch self {
        case .malformed(let reason):
            "Malformed HTTP request: \(reason)"
        }
    }
}

public struct HTTPResponseBuilder {
    public static func plain(status: Int, reason: String, body: String) -> Data {
        let bodyBytes = Array(body.utf8)
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(bodyBytes.count)\r
        Connection: close\r
        \r

        """
        var data = Data(header.utf8)
        data.append(contentsOf: bodyBytes)
        return data
    }
}
