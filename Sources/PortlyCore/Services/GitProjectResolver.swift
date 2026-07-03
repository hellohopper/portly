import Foundation

public enum GitProjectResolver {

    /// Resolves the working directory of a process, then walks up to find a git repo
    /// and returns (projectName, branchName). Returns nil fields when not applicable.
    public static func resolve(pid: Int32) -> (projectName: String?, gitBranch: String?) {
        guard let cwd = currentWorkingDirectory(of: pid) else { return (nil, nil) }
        guard let gitDir = findGitDir(startingAt: cwd) else {
            // Daemons run from "/" -- a bare slash is not a meaningful project name.
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            return (name == "/" ? nil : name, nil)
        }

        let projectRoot = gitDir.deletingLastPathComponent()
        let projectName = projectRoot.lastPathComponent
        let branch = readBranch(gitDir: gitDir)
        return (projectName, branch)
    }

    /// Public entry point for callers (e.g. quick-restart) that just need the cwd,
    /// without the git project/branch resolution.
    public static func workingDirectory(of pid: Int32) -> String? {
        currentWorkingDirectory(of: pid)
    }

    private static func currentWorkingDirectory(of pid: Int32) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        for line in output.split(separator: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }

    /// Walks up from `path` looking for a ".git" directory or file (worktrees use a file).
    static func findGitDir(startingAt path: String) -> URL? {
        var current = URL(fileURLWithPath: path)
        let fm = FileManager.default

        while true {
            let candidate = current.appendingPathComponent(".git")
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }

    static func readBranch(gitDir: URL) -> String? {
        var actualGitDir = gitDir

        // Worktrees: ".git" is a file (not a directory) containing
        // "gitdir: /path/to/real/.git/worktrees/<name>", which itself has its own HEAD.
        if let contents = try? String(contentsOf: gitDir, encoding: .utf8),
           contents.hasPrefix("gitdir:") {
            let realPath = contents
                .replacingOccurrences(of: "gitdir:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            actualGitDir = URL(fileURLWithPath: realPath)
        }

        let headURL = actualGitDir.appendingPathComponent("HEAD")
        guard let head = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        let trimmed = head.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst("ref: refs/heads/".count))
        }
        // Detached HEAD: show short commit hash.
        return String(trimmed.prefix(7))
    }
}
