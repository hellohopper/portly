import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A process's argv, read from the kernel (`KERN_PROCARGS2`) -- the same memory
/// `ps -o command` prints, including titles a process sets for itself
/// (`process.title = "npm run dev"`). Readable for the user's own processes; nil
/// for others', where callers fall back to `ps`.
enum ProcessArguments {

    private static let argumentMax: Int = {
        var mib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctl(&mib, 2, &value, &size, nil, 0) == 0 && value > 0 ? Int(value) : 256 * 1024
    }()

    static func argv(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = argumentMax
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parse(Array(buffer.prefix(size)))
    }

    /// Layout: `int argc`, the exec path, NUL padding, then argc NUL-terminated
    /// arguments (then the environment, which is ignored).
    static func parse(_ bytes: [UInt8]) -> [String]? {
        let intSize = MemoryLayout<Int32>.size
        guard bytes.count > intSize else { return nil }
        let argc = bytes.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        guard argc > 0 else { return nil }

        var index = intSize
        while index < bytes.count, bytes[index] != 0 { index += 1 } // exec path
        while index < bytes.count, bytes[index] == 0 { index += 1 } // padding

        var arguments: [String] = []
        while arguments.count < argc, index < bytes.count {
            let start = index
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            arguments.append(String(decoding: bytes[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments.isEmpty ? nil : arguments
    }

    /// The name `ps -o comm` shows, minus a login shell's leading "-": the last path
    /// component of argv[0].
    static func displayName(of pid: Int32) -> String? {
        guard let first = argv(of: pid)?.first, !first.isEmpty else { return nil }
        var name = (first as NSString).lastPathComponent
        if name.hasPrefix("-") { name.removeFirst() }
        return name.isEmpty ? nil : name
    }
}
