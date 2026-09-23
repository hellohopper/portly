import Foundation

/// Runs a short-lived helper process and captures its stdout.
///
/// Every call site used to hand `Process` an unread `standardError` pipe. That
/// deadlocks: a child that writes more than the ~64KB pipe buffer to stderr (e.g.
/// `lsof` warning about each unreachable network mount) blocks forever, never closes
/// stdout, and the reader blocks with it. Here stderr is drained concurrently with
/// stdout, and a timeout terminates a child that wedges anyway -- without one, a
/// single hung `lsof` freezes the whole port list permanently.
public enum Shell {

    /// Captured stdout, or nil if the process couldn't be launched, timed out, or
    /// produced output that isn't UTF-8.
    public static func run(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = 5
    ) -> String? {
        execute(path, arguments, timeout: timeout)?.output
    }

    /// Runs a process only for its exit status, discarding output. Success means a
    /// zero exit: stdout alone can't tell, since a failing command usually prints
    /// nothing to stdout, which reads as an empty (non-nil) string.
    @discardableResult
    public static func succeeds(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval = 5
    ) -> Bool {
        execute(path, arguments, timeout: timeout)?.status == 0
    }

    /// Stdout plus exit status, or nil if the process couldn't be launched or timed out.
    static func execute(
        _ path: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) -> (output: String?, status: Int32)? {
        guard let outPipe = Spawner.makePipe() else { return nil }
        guard let errPipe = Spawner.makePipe() else {
            close(outPipe.read); close(outPipe.write)
            return nil
        }

        // Spawned rather than run through `Process`: a `Process` child inherits every
        // stray descriptor the parent holds, including *other* concurrent helpers'
        // pipes -- and one child holding another's pipe open means that reader never
        // sees EOF. stdin is /dev/null: the CLI runs attached to a terminal, and an
        // interactive child (e.g. `zsh -i` reading PATH) must not contend for it.
        let pid: pid_t
        do {
            pid = try Spawner.spawn(
                executable: path, arguments: arguments,
                stdout: outPipe.write, stderr: errPipe.write, reap: false
            )
        } catch {
            [outPipe.read, outPipe.write, errPipe.read, errPipe.write].forEach { close($0) }
            return nil
        }
        // Only the child should hold the write ends, or the readers never see EOF.
        close(outPipe.write)
        close(errPipe.write)

        // Drain both pipes from this thread with poll(). Draining stderr is not
        // optional: it is the difference between "the child finishes" and "the child
        // blocks on a full stderr buffer forever". This used to park two blocking
        // reads per call on GCD worker threads; with enough of those (and other
        // blocked work) in flight, the readers could wait for a thread long enough to
        // hit the timeout -- which is how a plain `echo` came back nil on CI.
        let drained = drain(stdout: outPipe.read, stderr: errPipe.read, deadline: Date().addingTimeInterval(timeout))

        guard let output = drained else {
            // Timed out. SIGTERM, then SIGKILL anything that ignores it (an
            // interactive shell does) so the wait below can't hang.
            kill(pid, SIGTERM)
            if !exited(pid, within: 1) {
                kill(pid, SIGKILL)
                _ = Spawner.wait(for: pid)
            }
            return nil
        }

        let status = Spawner.wait(for: pid)
        return (String(data: output, encoding: .utf8), status)
    }

    /// Reads both descriptors to EOF (closing them), keeping stdout and discarding
    /// stderr. Nil if `deadline` passes first.
    private static func drain(stdout: Int32, stderr: Int32, deadline: Date) -> Data? {
        var descriptors = [
            pollfd(fd: stdout, events: Int16(POLLIN), revents: 0),
            pollfd(fd: stderr, events: Int16(POLLIN), revents: 0),
        ]
        defer {
            for descriptor in descriptors where descriptor.fd >= 0 { close(descriptor.fd) }
        }
        var output = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while descriptors.contains(where: { $0.fd >= 0 }) {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            let ready = poll(&descriptors, nfds_t(descriptors.count), Int32(min(remaining * 1000, 60_000)))
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            for index in descriptors.indices where descriptors[index].fd >= 0 && descriptors[index].revents != 0 {
                let count = read(descriptors[index].fd, &buffer, buffer.count)
                if count > 0 {
                    if index == 0 { output.append(buffer, count: count) }
                } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                    // EOF (or a hard error): this side is done. poll() skips fd -1.
                    close(descriptors[index].fd)
                    descriptors[index].fd = -1
                }
            }
        }
        return output
    }

    private static func exited(_ pid: pid_t, within seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        var status: Int32 = 0
        repeat {
            if waitpid(pid, &status, WNOHANG) != 0 { return true }
            usleep(20_000)
        } while Date() < deadline
        return false
    }
}
