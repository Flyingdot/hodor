import Foundation

/// Reads host aliases from ~/.ssh/config, to suggest them when adding a host.
public enum SSHConfig {
    /// Aliases from the user's ssh config. Empty if the file can't be read.
    public static func hostAliases() -> [String] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".ssh/config")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return hostAliases(in: text)
    }

    /// Names from `Host` lines, in file order and without duplicates.
    /// Patterns (`*`, `?`, `!`) are left out. `Include` is not followed.
    static func hostAliases(in text: String) -> [String] {
        var aliases: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            // "Host a b", "host a", "Host=a"
            guard line.count > 4, line.prefix(4).lowercased() == "host" else { continue }
            let rest = line.dropFirst(4)
            guard let first = rest.first, first == " " || first == "\t" || first == "=" else { continue }
            let names = rest.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "=" })
            for name in names.map(String.init) where !name.contains(where: { "*?!".contains($0) }) {
                if !aliases.contains(name) { aliases.append(name) }
            }
        }
        return aliases
    }
}
