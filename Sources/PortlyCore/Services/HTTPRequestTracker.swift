import Foundation

/// Follows the client side of an HTTP/1.x connection through the proxy and reports
/// each request line as it goes by -- including every request on a keep-alive
/// connection, not just the first.
///
/// Finding the next request means knowing where the current one's body ends, so
/// this tracks `Content-Length` and chunked transfer encoding. Anything it can't
/// frame (a protocol upgrade such as WebSockets, `CONNECT`, or malformed headers)
/// switches it off for the rest of the connection: from then on the bytes aren't
/// HTTP requests, and guessing would log garbage.
struct HTTPRequestTracker {

    private enum State {
        case headers(Data)
        case body(remaining: Int)
        case chunkSize(Data)
        case chunkData(remaining: Int)
        case chunkTrailer(Data)
        case opaque
    }

    /// Past this, a "header" is not a header; stop tracking rather than buffer it.
    static let maxHeaderBytes = 64 * 1024

    private var state: State = .headers(Data())

    /// Feeds the next bytes from the client; returns the request lines they completed.
    mutating func consume(_ data: Data) -> [String] {
        var requestLines: [String] = []
        var input = data[...]

        while !input.isEmpty {
            switch state {
            case .opaque:
                return requestLines

            case .headers(var buffer):
                buffer.append(contentsOf: input)
                input = Data()[...]
                guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                    state = buffer.count > Self.maxHeaderBytes ? .opaque : .headers(buffer)
                    continue
                }
                let head = buffer[buffer.startIndex..<end.lowerBound]
                let rest = buffer[end.upperBound...]
                guard let request = Self.parseHead(Data(head)) else {
                    state = .opaque
                    return requestLines
                }
                requestLines.append(request.line)
                switch request.body {
                case .none: state = .headers(Data())
                case .length(let length): state = length > 0 ? .body(remaining: length) : .headers(Data())
                case .chunked: state = .chunkSize(Data())
                case .opaque: state = .opaque
                }
                input = Data(rest)[...]

            case .body(let remaining):
                let taken = min(remaining, input.count)
                input = input.dropFirst(taken)
                state = remaining - taken > 0 ? .body(remaining: remaining - taken) : .headers(Data())

            case .chunkSize(var buffer):
                guard let newline = input.firstIndex(of: UInt8(ascii: "\n")) else {
                    buffer.append(contentsOf: input)
                    input = Data()[...]
                    state = buffer.count > 1024 ? .opaque : .chunkSize(buffer)
                    continue
                }
                buffer.append(contentsOf: input[input.startIndex...newline])
                input = input[input.index(after: newline)...]
                let line = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                let hex = line.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
                guard let size = Int(hex.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0 else {
                    state = .opaque
                    return requestLines
                }
                // A chunk is followed by CRLF; the last (size 0) by trailers + CRLF.
                state = size == 0 ? .chunkTrailer(Data()) : .chunkData(remaining: size + 2)

            case .chunkData(let remaining):
                let taken = min(remaining, input.count)
                input = input.dropFirst(taken)
                state = remaining - taken > 0 ? .chunkData(remaining: remaining - taken) : .chunkSize(Data())

            case .chunkTrailer(var buffer):
                buffer.append(contentsOf: input)
                input = Data()[...]
                // No trailers: just CRLF. Otherwise trailer lines end with a blank line.
                if buffer.starts(with: Data("\r\n".utf8)) {
                    state = .headers(Data())
                    input = Data(buffer.dropFirst(2))[...]
                } else if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    state = .headers(Data())
                    input = Data(buffer[end.upperBound...])[...]
                } else {
                    state = buffer.count > Self.maxHeaderBytes ? .opaque : .chunkTrailer(buffer)
                }
            }
        }
        return requestLines
    }

    private enum Body {
        case none
        case length(Int)
        case chunked
        /// The connection stops being HTTP requests after this one.
        case opaque
    }

    private static let methods: Set<String> = [
        "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "CONNECT", "TRACE",
    ]

    private static func parseHead(_ head: Data) -> (line: String, body: Body)? {
        let lines = String(decoding: head, as: UTF8.self).components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count == 3, methods.contains(String(parts[0])), parts[2].hasPrefix("HTTP/1.") else { return nil }

        var contentLength: Int?
        var chunked = false
        var upgrade = false
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).lowercased()
            switch name {
            case "content-length": contentLength = Int(value)
            case "transfer-encoding": chunked = value.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) == "chunked"
            case "upgrade": upgrade = true
            default: break
            }
        }

        if parts[0] == "CONNECT" || upgrade { return (requestLine, .opaque) }
        if chunked { return (requestLine, .chunked) }
        if let contentLength {
            guard contentLength >= 0 else { return nil }
            return (requestLine, .length(contentLength))
        }
        return (requestLine, .none)
    }
}
