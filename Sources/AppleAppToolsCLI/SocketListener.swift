import Darwin
import Foundation

final class SocketListener {
    let fd: Int32

    init(bindAddress: String, port: UInt16) throws {
        let listenFD = Darwin.socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard listenFD >= 0 else {
            throw SocketError.systemCall("socket", errno)
        }
        var yes: Int32 = 1
        if setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size)) != 0 {
            let err = errno
            close(listenFD)
            throw SocketError.systemCall("setsockopt SO_REUSEADDR", err)
        }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        if bindAddress.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) != 1 {
            close(listenFD)
            throw SocketError.invalidAddress(bindAddress)
        }
        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(listenFD, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let err = errno
            close(listenFD)
            throw SocketError.systemCall("bind \(bindAddress):\(port)", err)
        }
        guard Darwin.listen(listenFD, 16) == 0 else {
            let err = errno
            close(listenFD)
            throw SocketError.systemCall("listen", err)
        }
        self.fd = listenFD
    }

    deinit {
        close(fd)
    }

    struct AcceptedConnection {
        let fd: Int32
        let peerAddress: String?

        func readAll(maxBytes: Int) throws -> Data {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while data.count < maxBytes {
                let n = buffer.withUnsafeMutableBufferPointer { buf -> Int in
                    Darwin.recv(fd, buf.baseAddress, buf.count, 0)
                }
                if n < 0 {
                    throw SocketError.systemCall("recv", errno)
                }
                if n == 0 { break }
                data.append(buffer, count: n)
                if data.count >= 4,
                   data.range(of: Data("\r\n\r\n".utf8)) != nil,
                   contentLengthSatisfied(data: data) {
                    break
                }
            }
            return data
        }

        func writeAll(_ data: Data) throws -> Int {
            var written = 0
            try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let basePtr = raw.bindMemory(to: UInt8.self).baseAddress
                while written < data.count {
                    let n = Darwin.send(fd, basePtr?.advanced(by: written), data.count - written, 0)
                    if n < 0 {
                        throw SocketError.systemCall("send", errno)
                    }
                    if n == 0 { break }
                    written += n
                }
            }
            return written
        }

        private func contentLengthSatisfied(data: Data) -> Bool {
            guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
            let headerPart = data.subdata(in: 0..<separator.lowerBound)
            guard let headerText = String(data: headerPart, encoding: .utf8) else { return true }
            let lines = headerText.split(separator: "\r\n").map(String.init)
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                if key == "content-length",
                   let length = Int(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)) {
                    let bodyLength = data.count - separator.upperBound
                    return bodyLength >= length
                }
            }
            return true
        }
    }

    func accept() throws -> AcceptedConnection {
        var addr = sockaddr_storage()
        var len = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let connFD = withUnsafeMutablePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.accept(fd, sockPtr, &len)
            }
        }
        guard connFD >= 0 else {
            throw SocketError.systemCall("accept", errno)
        }
        var host = [UInt8](repeating: 0, count: Int(NI_MAXHOST))
        let ni = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                host.withUnsafeMutableBufferPointer { buf in
                    getnameinfo(sockPtr, len, buf.baseAddress.map { UnsafeMutablePointer<CChar>(OpaquePointer($0)) }, socklen_t(buf.count), nil, 0, NI_NUMERICHOST)
                }
            }
        }
        let peer: String?
        if ni == 0 {
            let nullTerminated = host.prefix(while: { $0 != 0 })
            peer = String(decoding: nullTerminated, as: UTF8.self)
        } else {
            peer = nil
        }
        return AcceptedConnection(fd: connFD, peerAddress: peer)
    }
}

enum SocketError: Error, CustomStringConvertible {
    case systemCall(String, Int32)
    case invalidAddress(String)

    var description: String {
        switch self {
        case .systemCall(let name, let err):
            "\(name) failed: errno=\(err) (\(String(cString: strerror(err))))"
        case .invalidAddress(let address):
            "invalid bind address: \(address)"
        }
    }
}
