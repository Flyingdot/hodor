import Foundation

/// The `hodor` command agents run, at `~/.hodor/hodor` on this Mac and on every host.
/// It sends its arguments to Hodor's control socket with curl and prints the reply.
/// Exits 1 when Hodor rejects the command and 2 when Hodor can't be reached.
public enum AgentScript {
    /// `~/.hodor` on this Mac. Hosts get the same folder in their home directory.
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hodor")
    }

    /// The control socket on this Mac. Hosts reach it through `~/.hodor/hodor.sock` there.
    public static var socketPath: String {
        directory.appendingPathComponent("hodor.sock").path
    }

    public static let source = """
        #!/bin/sh
        # Steers the Hodor menu bar app on the user's Mac. Installed by Hodor, run `hodor help`.
        sock="${HODOR_SOCKET:-$HOME/.hodor/hodor.sock}"
        [ $# -gt 0 ] || set -- help
        unreachable() {
          echo "hodor: can't reach Hodor through $sock. The app isn't running or lost its connection to this machine." >&2
          exit 2
        }
        [ -S "$sock" ] || unreachable
        resp=$(printf '%s\\n' "$@" | curl -sS --unix-socket "$sock" --data-binary @- -w '\\n%{http_code}' http://hodor/) || unreachable
        code=$(printf '%s\\n' "$resp" | tail -n 1)
        body=$(printf '%s\\n' "$resp" | sed '$d')
        if [ "$code" = 200 ]; then
          printf '%s\\n' "$body"
        else
          printf '%s\\n' "$body" >&2
          exit 1
        fi

        """

    /// Writes the script to `~/.hodor/hodor` on this Mac.
    public static func installLocally() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("hodor")
        try Data(source.utf8).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
