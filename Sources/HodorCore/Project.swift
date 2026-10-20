import Foundation

/// A fixed local URL (e.g. https://localhost:4200) that gets forwarded to a dev server on a remote host,
/// plus optional extra ports to the same host.
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    /// ssh host that all forwards of the project go to.
    public var host: String?
    /// Port of the selected dev server on `host`, for the URL's port.
    public var remotePort: Int?
    /// Forwards the URL's port to the same port on `host`, without picking a server.
    public var samePort: Bool
    /// Ports forwarded in addition to the URL's port.
    public var extraForwards: [Forward]
    public var isActive: Bool

    public init(
        id: UUID = UUID(), name: String, url: String, host: String? = nil, remotePort: Int? = nil, samePort: Bool = false,
        extraForwards: [Forward] = [], isActive: Bool = false
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.host = host
        self.remotePort = remotePort
        self.samePort = samePort
        self.extraForwards = extraForwards
        self.isActive = isActive
    }

    /// Configs written before extra forwards have neither `samePort` nor `extraForwards`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        host = try container.decodeIfPresent(String.self, forKey: .host)
        remotePort = try container.decodeIfPresent(Int.self, forKey: .remotePort)
        samePort = try container.decodeIfPresent(Bool.self, forKey: .samePort) ?? false
        extraForwards = try container.decodeIfPresent([Forward].self, forKey: .extraForwards) ?? []
        isActive = try container.decode(Bool.self, forKey: .isActive)
    }

    /// The URL's port first, then the extra forwards. Without a port in the URL, only the extra forwards.
    public var forwards: [Forward] {
        guard let localPort else { return extraForwards }
        return [Forward(localPort: localPort, samePort: samePort, remotePort: remotePort)] + extraForwards
    }

    /// Whether there is a host and every forward has a target, i.e. the project can be activated.
    public var isComplete: Bool {
        host != nil && localPort != nil && forwards.allSatisfy { $0.target != nil }
    }

    /// Sets the picked server of the forward at `index` in `forwards`. All forwards go through one ssh connection,
    /// so picking a server on another host clears the servers picked for the other forwards.
    public mutating func pick(_ port: Int?, on host: String?, forwardAt index: Int) {
        if let host, host != self.host {
            self.host = host
            clearPicks()
        }
        if localPort != nil && index == 0 {
            remotePort = port
        } else {
            extraForwards[index - (localPort == nil ? 0 : 1)].remotePort = port
        }
    }

    /// Clears the picked server of every forward. Same-port forwards are unaffected.
    public mutating func clearPicks() {
        remotePort = nil
        for index in extraForwards.indices {
            extraForwards[index].remotePort = nil
        }
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

/// One local port of a project and the port it goes to on the project's host.
public struct Forward: Codable, Hashable, Sendable {
    public var localPort: Int
    /// Forwards to the same port on the remote, without picking a server.
    public var samePort: Bool
    /// Port of the picked dev server. Unused when `samePort` is on.
    public var remotePort: Int?

    public init(localPort: Int, samePort: Bool = true, remotePort: Int? = nil) {
        self.localPort = localPort
        self.samePort = samePort
        self.remotePort = remotePort
    }

    /// A hand-written `{"localPort": 10000}` is a same-port forward.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        localPort = try container.decode(Int.self, forKey: .localPort)
        samePort = try container.decodeIfPresent(Bool.self, forKey: .samePort) ?? true
        remotePort = try container.decodeIfPresent(Int.self, forKey: .remotePort)
    }

    /// Remote port the tunnel forwards to. Nil while no server is picked.
    public var target: Int? {
        samePort ? localPort : remotePort
    }

    /// Parses "5000", "10000-10002" or a list of both separated by commas or spaces.
    /// Nil for anything else, a port outside 1–65535 or more than 100 ports in total.
    public static func parsePorts(_ text: String) -> [Int]? {
        let parts = text.split { $0 == "," || $0.isWhitespace }
        guard !parts.isEmpty else { return nil }
        var ports: [Int] = []
        for part in parts {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
            guard bounds.count <= 2, let low = bounds.first ?? nil, let high = bounds.last ?? nil,
                1 <= low, low <= high, high <= 65535, high - low < 100
            else { return nil }
            ports += low...high
        }
        return ports.count <= 100 ? ports : nil
    }
}

/// A TCP listener found on the remote host.
public struct DevServer: Hashable, Identifiable, Sendable {
    public var port: Int
    public var pid: Int?
    /// Executable name, e.g. "node" or "dcp".
    public var process: String?
    /// Working directory of the process, usually somewhere in a worktree.
    public var directory: String?
    /// Top level of the git worktree that contains `directory`.
    public var worktreePath: String?
    /// The repository's shared git directory, e.g. /home/dani/dev/app/.git for all of its worktrees.
    public var gitCommonDir: String?
    /// Checked out branch. Nil when HEAD is detached.
    public var branch: String?

    public var id: Int { port }

    public init(
        port: Int, pid: Int? = nil, process: String? = nil, directory: String? = nil,
        worktreePath: String? = nil, gitCommonDir: String? = nil, branch: String? = nil
    ) {
        self.port = port
        self.pid = pid
        self.process = process
        self.directory = directory
        self.worktreePath = worktreePath
        self.gitCommonDir = gitCommonDir
        self.branch = branch
    }

    /// Whether the listener is likely a dev server: one of your processes, running inside a git worktree.
    public var isDevServer: Bool {
        pid != nil && worktreePath != nil
    }

    /// Repository name: the folder holding `.git`, or a bare repo's name without `.git`.
    public var repository: String? {
        // Remote paths are handled as strings. A file URL would stat them on this Mac, which is slow under /home.
        guard let gitCommonDir = gitCommonDir as NSString? else { return nil }
        if gitCommonDir.lastPathComponent == ".git" {
            return (gitCommonDir.deletingLastPathComponent as NSString).lastPathComponent
        }
        return (gitCommonDir.lastPathComponent as NSString).deletingPathExtension
    }

    /// Folder name of the worktree.
    public var worktree: String? {
        worktreePath.map { ($0 as NSString).lastPathComponent }
    }

    /// Whether the worktree is the repository's main checkout rather than a linked worktree.
    public var isMainCheckout: Bool {
        guard let worktreePath, let gitCommonDir else { return false }
        return (gitCommonDir as NSString).deletingLastPathComponent == worktreePath
    }

    /// `directory` relative to the worktree. Nil at the worktree's top level or outside a worktree.
    public var subdirectory: String? {
        guard let worktreePath, let directory, directory.hasPrefix(worktreePath + "/") else { return nil }
        return String(directory.dropFirst(worktreePath.count + 1))
    }
}

public enum TunnelStatus: Equatable, Sendable {
    case inactive
    case running
    case failed(String)
}
