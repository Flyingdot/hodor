import Foundation

/// A fixed local URL (e.g. https://localhost:4200) that gets forwarded to one dev server on the remote host.
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    /// Port of the selected dev server on the remote host.
    public var remotePort: Int?
    public var isActive: Bool

    public init(id: UUID = UUID(), name: String, url: String, remotePort: Int? = nil, isActive: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.remotePort = remotePort
        self.isActive = isActive
    }

    /// Local port taken from the URL. Falls back to the scheme's default port.
    public var localPort: Int? {
        Project.localPort(of: url)
    }

    public static func localPort(of url: String) -> Int? {
        guard let components = URLComponents(string: url), let host = components.host, !host.isEmpty else { return nil }
        if let port = components.port { return port }
        switch components.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }
}

/// A TCP listener found on the remote host.
public struct DevServer: Hashable, Identifiable, Sendable {
    public var port: Int
    public var pid: Int?
    /// Process name, e.g. "node".
    public var process: String?
    /// Working directory of the process, usually the worktree.
    public var directory: String?

    public var id: Int { port }

    public init(port: Int, pid: Int? = nil, process: String? = nil, directory: String? = nil) {
        self.port = port
        self.pid = pid
        self.process = process
        self.directory = directory
    }
}

public enum TunnelStatus: Equatable, Sendable {
    case inactive
    case running
    case failed(String)
}
