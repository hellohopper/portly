import Testing
@testable import PortlyCore

struct KeyboardNavigatorTests {

    private let ports = [3000, 5173, 8000]

    @Test func downFromNothingFocusesFirst() {
        #expect(KeyboardNavigator.move(from: nil, in: ports, direction: .down) == 3000)
    }

    @Test func upFromNothingFocusesLast() {
        #expect(KeyboardNavigator.move(from: nil, in: ports, direction: .up) == 8000)
    }

    @Test func downMovesToNext() {
        #expect(KeyboardNavigator.move(from: 3000, in: ports, direction: .down) == 5173)
    }

    @Test func upMovesToPrevious() {
        #expect(KeyboardNavigator.move(from: 5173, in: ports, direction: .up) == 3000)
    }

    @Test func clampsAtEndsInsteadOfWrapping() {
        #expect(KeyboardNavigator.move(from: 8000, in: ports, direction: .down) == 8000)
        #expect(KeyboardNavigator.move(from: 3000, in: ports, direction: .up) == 3000)
    }

    @Test func vanishedFocusRestartsFromEdge() {
        // The focused port was killed or filtered out of the visible list.
        #expect(KeyboardNavigator.move(from: 4444, in: ports, direction: .down) == 3000)
        #expect(KeyboardNavigator.move(from: 4444, in: ports, direction: .up) == 8000)
    }

    @Test func emptyListYieldsNoFocus() {
        #expect(KeyboardNavigator.move(from: 3000, in: [Int](), direction: .down) == nil)
        #expect(KeyboardNavigator.move(from: Int?.none, in: [Int](), direction: .up) == nil)
    }

    /// Navigation is driven by row identity, not port number, because two processes
    /// can listen on the same port on different local addresses.
    @Test func navigatesRowIdentifiers() {
        let rows = ["100-3000", "200-3000", "300-8000"]
        #expect(KeyboardNavigator.move(from: nil, in: rows, direction: .down) == "100-3000")
        #expect(KeyboardNavigator.move(from: "100-3000", in: rows, direction: .down) == "200-3000")
        #expect(KeyboardNavigator.move(from: "300-8000", in: rows, direction: .down) == "300-8000")
    }
}
