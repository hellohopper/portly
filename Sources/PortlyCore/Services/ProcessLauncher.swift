import Foundation

/// Relaunches a recorded command line in its original working directory.
public enum ProcessLauncher {

    /// Splits a `ps`-style command line into argv.
    ///
    /// `ps -o command=` joins argv with spaces and no quoting, so this can't recover
    /// an argument that genuinely contained a space. Splitting is still the right
    /// call: the alternative, handing the string to `sh -c`, would additionally
    /// glob-expand `*` and interpret `;`, `&&` and `$` -- running something the user
    /// never typed.
    public static func argv(from commandLine: String) -> [String] {
        commandLine.split(separator: " ").map(String.init)
    }

    @discardableResult
    public static func launch(commandLine: String, workingDirectory: String?) -> Bool {
        launchProcess(commandLine: commandLine, workingDirectory: workingDirectory) != nil
    }

    /// Resolves argv[0] against the user's real PATH (see `ExecutableResolver`) and
    /// starts it, returning its pid. Returns nil when the executable can't be found
    /// or won't start -- resolving up front is what makes that detectable: going
    /// through `/usr/bin/env` meant `env` always launched, so a missing `node`
    /// reported success while the server stayed dead.
    ///
    /// Spawned with only stdio inherited (see `Spawner`): a dev server outlives
    /// Portly, and must not keep Portly's pipes and sockets open for its lifetime.
    @discardableResult
    public static func launchProcess(
        commandLine: String,
        workingDirectory: String?
    ) -> pid_t? {
        let argv = argv(from: commandLine)
        guard let name = argv.first, let executable = ExecutableResolver.resolve(name) else { return nil }

        let directory = workingDirectory.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
        return try? Spawner.spawn(
            executable: executable,
            arguments: Array(argv.dropFirst()),
            // The child needs the same PATH: `npm` is itself a `#!/usr/bin/env node` script.
            environment: ExecutableResolver.environment(
                prepending: (executable as NSString).deletingLastPathComponent
            ),
            workingDirectory: directory,
            stdout: STDOUT_FILENO,
            stderr: STDERR_FILENO
        )
    }
}
