import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Starts child processes with *only* the descriptors they're given.
///
/// Foundation's `Process` lets a child inherit every descriptor the parent has open
/// without close-on-exec -- including other helpers' pipes. With several helpers
/// running at once, one child holding another's pipe open means that reader never
/// sees EOF, so a plain `echo` would time out. And a long-lived child (a relaunched
/// dev server, a daemon started from a login shell) would pin Portly's descriptors
/// for as long as it lives. `POSIX_SPAWN_CLOEXEC_DEFAULT` closes everything except
/// the three stdio slots set up here.
public enum Spawner {

    public struct SpawnError: Error, Equatable {
        public let code: Int32
    }

    /// Spawns `executable` (an absolute path; no PATH search) and returns its pid.
    ///
    /// - `stdin`/`stdout`/`stderr`: descriptors to install as 0/1/2, or nil for
    ///   /dev/null.
    /// - The child gets its own process group, so a Ctrl+C aimed at the CLI (or a
    ///   signal to Portly's group) doesn't take down servers it started.
    /// - `reap`: when true, the child is waited for in the background once it exits,
    ///   so a long-lived process that eventually dies doesn't linger as a zombie.
    ///   Callers that `wait(for:)` themselves pass false.
    public static func spawn(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        stdin: Int32? = nil,
        stdout: Int32? = nil,
        stderr: Int32? = nil,
        reap: Bool = true
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        for (source, target) in [(stdin, STDIN_FILENO), (stdout, STDOUT_FILENO), (stderr, STDERR_FILENO)] {
            if let source {
                posix_spawn_file_actions_adddup2(&fileActions, source, target)
            } else {
                posix_spawn_file_actions_addopen(
                    &fileActions, target, "/dev/null", target == STDIN_FILENO ? O_RDONLY : O_WRONLY, 0
                )
            }
        }
        if let workingDirectory {
            posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
        }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        )
        posix_spawnattr_setpgroup(&attributes, 0)
        // Don't pass on signals the parent ignores (e.g. SIGPIPE) or has blocked.
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let environmentStrings = (environment ?? ProcessInfo.processInfo.environment)
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { environmentStrings.forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable, &fileActions, &attributes, argv, environmentStrings)
        guard result == 0 else { throw SpawnError(code: result) }
        if reap { reapWhenExited(pid) }
        return pid
    }

    /// Blocks until `pid` exits and returns its exit status (128+signal when killed).
    public static func wait(for pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            guard errno == EINTR else { return -1 }
        }
        return exitCode(fromWaitStatus: status)
    }

    static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    private static let reaperQueue = DispatchQueue(label: "dev.hellohopper.portly.reaper")
    private static let reaperLock = NSLock()
    nonisolated(unsafe) private static var reapers: [pid_t: DispatchSourceProcess] = [:]

    private static func reapWhenExited(_ pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: reaperQueue)
        source.setEventHandler {
            var status: Int32 = 0
            _ = waitpid(pid, &status, WNOHANG)
            source.cancel()
            reaperLock.lock()
            reapers[pid] = nil
            reaperLock.unlock()
        }
        reaperLock.lock()
        reapers[pid] = source
        reaperLock.unlock()
        source.resume()
        // It may already have exited before the source was armed.
        reaperQueue.async {
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == pid {
                reaperLock.lock()
                reapers[pid]?.cancel()
                reapers[pid] = nil
                reaperLock.unlock()
            }
        }
    }

    /// A pipe whose ends are close-on-exec, so no child -- ours or one Foundation
    /// spawns concurrently -- inherits it except through an explicit dup2.
    static func makePipe() -> (read: Int32, write: Int32)? {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        return (fds[0], fds[1])
    }
}
