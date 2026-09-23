import Testing
import Foundation
@testable import PortlyCore

struct HTTPRequestTrackerTests {

    private func feed(_ chunks: [String]) -> [String] {
        var tracker = HTTPRequestTracker()
        return chunks.flatMap { tracker.consume(Data($0.utf8)) }
    }

    @Test func logsEveryRequestOnAKeepAliveConnection() {
        let lines = feed([
            "GET /a HTTP/1.1\r\nHost: x\r\n\r\n",
            "GET /b HTTP/1.1\r\nHost: x\r\n\r\nGET /c HTTP/1.1\r\nHost: x\r\n\r\n",
        ])
        #expect(lines == ["GET /a HTTP/1.1", "GET /b HTTP/1.1", "GET /c HTTP/1.1"])
    }

    /// The case the old first-bytes check missed: the next request starts in the
    /// same read as the previous body.
    @Test func skipsContentLengthBodiesIncludingOnesThatLookLikeRequests() {
        let body = "GET /not-a-request HTTP/1.1\r\n\r\n"
        let lines = feed([
            "POST /upload HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)GET /next HTTP/1.1\r\n\r\n",
        ])
        #expect(lines == ["POST /upload HTTP/1.1", "GET /next HTTP/1.1"])
    }

    @Test func handlesRequestsSplitAcrossReads() {
        let lines = feed(["POST /x HTTP/1.1\r\nContent-Le", "ngth: 5\r\n\r\nhel", "loGET /y HTTP/1.1\r", "\n\r\n"])
        #expect(lines == ["POST /x HTTP/1.1", "GET /y HTTP/1.1"])
    }

    @Test func followsChunkedBodiesAndTrailers() {
        let lines = feed([
            "POST /stream HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n",
            "5\r\nhello\r\n1a;ext=1\r\nGET /inside HTTP/1.1\r\n\r\nxx\r\n",
            "0\r\nX-Trailer: 1\r\n\r\nGET /after HTTP/1.1\r\n\r\n",
            "POST /again HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\nDELETE /last HTTP/1.1\r\n\r\n",
        ])
        #expect(lines == ["POST /stream HTTP/1.1", "GET /after HTTP/1.1", "POST /again HTTP/1.1", "DELETE /last HTTP/1.1"])
    }

    /// After an upgrade the bytes are WebSocket frames, not requests.
    @Test func stopsAtProtocolUpgrades() {
        let lines = feed([
            "GET /socket HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n",
            "GET /looks-like-http HTTP/1.1\r\n\r\n",
        ])
        #expect(lines == ["GET /socket HTTP/1.1"])
    }

    @Test func stopsOnNonHTTPTraffic() {
        #expect(feed(["\u{16}\u{03}\u{01} tls hello\r\n\r\n", "GET / HTTP/1.1\r\n\r\n"]).isEmpty)
    }
}
