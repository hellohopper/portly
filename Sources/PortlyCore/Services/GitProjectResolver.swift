import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum GitProjectResolver {

    /// Resolves the working directory of a process, then walks up to find a git repo
    /// and returns (projectName, branchName). Returns nil fields when not applicable.
    public static func resolve(pid: Int32) -> (projectName: String?, gitBranch: String?) {
        guard let cwd = currentWorkingDirectory(of: pid) else { return (nil, nil) }
        return resolve(workingDirectory: cwd)
    }

    /// Everything `resolve(pid:)` does once the cwd is known. Callers that need the
    /// cwd too should resolve it once and use this -- the pid-based entry point used
    /// to be paired with a second `workingDirectory(of:)` call, spawning `lsof` twice
    /// for the same process.
    public static func resolve(workingDirectory cwd: String) -> (projectName: String?, gitBranch: String?) {
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

    /// The git root above `directory`, or `directory` itself when it isn't in a git
    /// repo -- the directory a per-project config file (e.g. `.portly.json`) belongs at.
    public static func projectRoot(fromDirectory directory: String) -> URL {
        findGitDir(startingAt: directory)?.deletingLastPathComponent() ?? URL(fileURLWithPath: directory)
    }

    /// A process's cwd, straight from the kernel.
    ///
    /// This used to shell out to `lsof` -- the last place in the app whose subprocess
    /// count grew with the number of listening ports, since it runs once per newly
    /// seen pid. `proc_pidinfo` answers the same question with a syscall.
    ///
    /// It returns nothing for processes owned by another user (reading their vnode
    /// info needs root), exactly like the `lsof` version did, so callers already
    /// handle a nil cwd.
    static func currentWorkingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let written = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard written == size else { return nil }

        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? nil : path
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
