import Foundation

/// A fixed local URL (e.g. https://localhost:4200) that gets forwarded to one dev server on a remote host.
public struct Project: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    /// ssh host of the selected dev server.
    public var host: String?
    /// Port of the selected dev server on `host`.
    public var remotePort: Int?
    public var isActive: Bool

    public init(id: UUID = UUID(), name: String, url: String, host: String? = nil, remotePort: Int? = nil, isActive: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.host = host
        self.remotePort = remotePort
        self.isActive = isActive
    }

    /// Whether a dev server is selected, i.e. the project can be activated.
    public var hasServer: Bool {
        host != nil && remotePort != nil
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
        guard let gitCommonDir else { return nil }
        let url = Self.remoteURL(gitCommonDir)
        if url.lastPathComponent == ".git" { return url.deletingLastPathComponent().lastPathComponent }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Folder name of the worktree.
    public var worktree: String? {
        worktreePath.map { Self.remoteURL($0).lastPathComponent }
    }

    /// Whether the worktree is the repository's main checkout rather than a linked worktree.
    public var isMainCheckout: Bool {
        guard let worktreePath, let gitCommonDir else { return false }
        return Self.remoteURL(gitCommonDir).deletingLastPathComponent().path == worktreePath
    }

    /// URL of a directory on the remote host. Without the hint, Foundation stats the path on this Mac, which is
    /// slow under `/home` (autofs) and ran on every render of the server picker.
    private static func remoteURL(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
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
