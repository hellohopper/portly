import Testing
@testable import Portly

struct NettopLineParserTests {

    @Test func recognizesHeaderLine() {
        #expect(NettopLineParser.isHeaderLine("time,,bytes_in,bytes_out,"))
    }

    @Test func doesNotTreatDataLineAsHeader() {
        #expect(!NettopLineParser.isHeaderLine("00:39:57.871638,apsd.576,0,0,"))
    }

    @Test func parsesSimpleProcessName() {
        let sample = NettopLineParser.parseDataLine("00:39:57.871638,apsd.576,120,340,")
        #expect(sample == NettopLineParser.Sample(pid: 576, bytesIn: 120, bytesOut: 340))
    }

    @Test func parsesProcessNameContainingDots() {
        // Process names can themselves contain dots (e.g. bundle-id-style names), so the
        // pid must be taken from the *last* dot-separated segment, not the first.
        let sample = NettopLineParser.parseDataLine("00:39:56.876945,ch.protonvpn.ma.20859,417098464,236632200,")
        #expect(sample == NettopLineParser.Sample(pid: 20859, bytesIn: 417098464, bytesOut: 236632200))
    }

    @Test func returnsNilForHeaderLine() {
        #expect(NettopLineParser.parseDataLine("time,,bytes_in,bytes_out,") == nil)
    }

    @Test func returnsNilForBlankLine() {
        #expect(NettopLineParser.parseDataLine("") == nil)
    }

    @Test func returnsNilWhenPidSegmentIsNotNumeric() {
        #expect(NettopLineParser.parseDataLine("00:39:57.871638,noPidHere,120,340,") == nil)
    }

    @Test func returnsNilWhenTooFewFields() {
        #expect(NettopLineParser.parseDataLine("00:39:57.871638,apsd.576") == nil)
    }
}
