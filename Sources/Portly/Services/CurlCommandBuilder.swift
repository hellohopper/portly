import Foundation

enum CurlCommandBuilder {
    /// Ready-to-paste curl invocation for a local port. `-i` includes the status
    /// line and response headers, which is what you usually want when poking a
    /// dev server to see if it's alive and what it returns.
    static func command(port: Int) -> String {
        "curl -i http://localhost:\(port)/"
    }
}
