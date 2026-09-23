import Foundation

/// Finds executables the way the user's own terminal would.
///
/// A menu bar app launched from Finder inherits launchd's PATH
/// (`/usr/bin:/bin:/usr/sbin:/sbin`), so `/usr/bin/env node` or `cloudflared` from
/// Homebrew, nvm, bun, cargo, ... simply isn't found -- and because `env` itself
/// launched fine, the failure used to look like success. This merges the inherited
/// PATH, the common tool directories, and (once, lazily) the PATH a login shell
/// reports, then resolves names against that.
public enum ExecutableResolver {

    /// Directories package managers install into, checked even when neither the
    /// inherited PATH nor the login shell mention them.
    static var wellKnownDirectories: [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.deno/bin",
            "\(home)/.cargo/bin",
            "\(home)/.volta/bin",
            "\(home)/Library/pnpm",
        ]
    }

    /// The merged search path, in priority order, without duplicates. Resolved once:
    /// asking the login shell costs a process launch (and whatever the user's rc
    /// files do), so callers that care about latency should warm this up early.
    public static let searchPath: [String] = {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return deduplicated(inherited + loginShellPath() + wellKnownDirectories + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"])
    }()

    /// `searchPath` as a PATH string, for a child's environment -- so a script's
    /// `#!/usr/bin/env node` shebang resolves too, not just the top-level command.
    public static var pathVariable: String {
        searchPath.joined(separator: ":")
    }

    /// Absolute path to `name`, or nil when nothing executable by that name exists.
    /// A name containing a slash is taken as a path and only checked.
    public static func resolve(_ name: String) -> String? {
        resolve(name, in: searchPath)
    }

    static func resolve(_ name: String, in directories: [String]) -> String? {
        guard !name.isEmpty else { return nil }
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for directory in directories where !directory.isEmpty {
            let candidate = (directory as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory),
               !isDirectory.boolValue,
               FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// The current environment with PATH replaced by `searchPath`.
    public static func environment(prepending extraDirectory: String? = nil) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let directories = deduplicated((extraDirectory.map { [$0] } ?? []) + searchPath)
        environment["PATH"] = directories.joined(separator: ":")
        return environment
    }

    /// PATH as an interactive login shell sees it -- `-i` because nvm and friends
    /// hook in from `.zshrc`, which a non-interactive shell never reads. Output is
    /// fenced with markers since rc files are free to print banners.
    static func loginShellPath() -> [String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let marker = "__PORTLY_PATH__"
        guard let output = Shell.run(shell, ["-ilc", "printf '\(marker)%s\(marker)' \"$PATH\""], timeout: 3) else {
            return []
        }
        return parseMarkedPath(output, marker: marker)
    }

    static func parseMarkedPath(_ output: String, marker: String) -> [String] {
        let parts = output.components(separatedBy: marker)
        guard parts.count >= 3 else { return [] }
        return parts[1].split(separator: ":").map(String.init)
    }

    static func deduplicated(_ directories: [String]) -> [String] {
        var seen = Set<String>()
        return directories.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
