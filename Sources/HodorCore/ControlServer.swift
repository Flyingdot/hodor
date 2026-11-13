import Darwin
import Foundation

/// Serves agent commands as plain HTTP on a Unix socket, which the `hodor` script reaches with
/// `curl --unix-socket`. The request body holds one argument per line. The reply is text, status 200 when the
/// command worked and 400 when it didn't. The socket is only accessible to the user (0600 in a 0700 folder).
public final class ControlServer: @unchecked Sendable {
    public typealias Handler = @Sendable ([String]) async -> AgentControl.Reply

    public let path: String
    private let handler: Handler
    private let queue = DispatchQueue(label: "ch.meimail.hodor.control")
    /// Only touched on the thread that calls `start` and `stop` (the main thread in the app).
    private var source: DispatchSourceRead?

    struct Failure: LocalizedError {
        var errorDescription: String?
    }

    /// Requests larger than this are dropped.
    static let maxRequest = 64 * 1024

    public init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    public var isRunning: Bool { source != nil }

    /// Creates the socket, replacing a stale one left by an earlier run.
    public func start() throws {
        guard source == nil else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Self.posixFailure("socket") }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw Failure(errorDescription: "The socket path \(path) is too long.")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(fd, 16) == 0 else {
            let failure = Self.posixFailure("bind \(path)")
            close(fd)
            throw failure
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptAll(fd) }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        guard let source else { return }
        source.cancel()
        self.source = nil
        unlink(path)
    }

    private func acceptAll(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            // Accepted sockets inherit O_NONBLOCK; reading is simpler blocking, with a timeout.
            _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 10, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            DispatchQueue.global().async { [handler] in
                guard let args = Self.readRequest(client) else {
                    close(client)
                    return
                }
                Task {
                    let reply = await handler(args)
                    Self.respond(client, reply)
                    close(client)
                }
            }
        }
    }

    /// Reads one HTTP request and returns its body's lines. Nil for a broken or oversized request.
    static func readRequest(_ client: Int32) -> [String]? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let separator = Data("\r\n\r\n".utf8)
        var bodyStart: Int?
        var length = 0
        while true {
            if bodyStart == nil, let range = data.range(of: separator) {
                bodyStart = range.upperBound
                let header = String(decoding: data[..<range.lowerBound], as: UTF8.self)
                for line in header.split(separator: "\r\n") {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    if parts.count == 2, parts[0].lowercased() == "content-length" {
                        length = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
            }
            if let bodyStart, data.count - bodyStart >= length {
                let body = String(decoding: data[bodyStart..<(bodyStart + length)], as: UTF8.self)
                var lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                if body.hasSuffix("\n") { lines.removeLast() }
                return lines
            }
            guard data.count < maxRequest else { return nil }
            let count = read(client, &buffer, buffer.count)
            guard count > 0 else { return nil }
            data.append(contentsOf: buffer[0..<count])
        }
    }

    static func respond(_ client: Int32, _ reply: AgentControl.Reply) {
        let body = Data((reply.text + "\n").utf8)
        let head =
            "HTTP/1.1 \(reply.ok ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        let response = Data(head.utf8) + body
        response.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(client, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }

    private static func posixFailure(_ what: String) -> Failure {
        Failure(errorDescription: "\(what): \(String(cString: strerror(errno)))")
    }
}
