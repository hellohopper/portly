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
        let argv = argv(from: commandLine)
        guard let executable = argv.first else { return false }

        let process = Process()
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(argv.dropFirst())
        } else {
            // A bare name (e.g. "node") needs PATH resolution, which Process doesn't
            // do; env does, without involving a shell.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = argv
        }
        if let workingDirectory, FileManager.default.fileExists(atPath: workingDirectory) {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
