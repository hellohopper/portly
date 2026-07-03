import Foundation
import Testing
@testable import Portly

@MainActor
struct HistoryStoreTests {

    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("portly-history-test-\(UUID().uuidString)/history.json")
    }

    private func makeInfo(port: Int, processName: String = "node", projectName: String? = "web") -> PortInfo {
        var info = PortInfo(pid: 100, port: port, proto: "TCP", processName: processName, commandPath: nil)
        info.projectName = projectName
        return info
    }

    @Test func recordsOpenedAndClosedEventsNewestFirst() {
        let store = HistoryStore(fileURL: tempFileURL())

        store.record(opened: [makeInfo(port: 3000)], closed: [], at: Date(timeIntervalSince1970: 100))
        store.record(opened: [], closed: [makeInfo(port: 3000)], at: Date(timeIntervalSince1970: 200))

        #expect(store.events.count == 2)
        #expect(store.events[0].kind == .closed)
        #expect(store.events[1].kind == .opened)
        #expect(store.events[0].port == 3000)
        #expect(store.events[0].projectName == "web")
    }

    @Test func emptyDiffRecordsNothing() {
        let store = HistoryStore(fileURL: tempFileURL())
        store.record(opened: [], closed: [])
        #expect(store.events.isEmpty)
    }

    @Test func capsAtMaxEvents() {
        let store = HistoryStore(fileURL: tempFileURL())
        for port in 0..<(HistoryStore.maxEvents + 50) {
            store.record(opened: [makeInfo(port: port)], closed: [])
        }
        #expect(store.events.count == HistoryStore.maxEvents)
        // Newest survives the cap.
        #expect(store.events.first?.port == HistoryStore.maxEvents + 49)
    }

    @Test func persistsAcrossInstances() {
        let url = tempFileURL()
        let first = HistoryStore(fileURL: url)
        first.record(opened: [makeInfo(port: 3000)], closed: [], at: Date(timeIntervalSince1970: 100))

        let second = HistoryStore(fileURL: url)
        #expect(second.events == first.events)
    }

    @Test func clearEmptiesEventsAndPersistence() {
        let url = tempFileURL()
        let store = HistoryStore(fileURL: url)
        store.record(opened: [makeInfo(port: 3000)], closed: [])
        store.clear()

        #expect(store.events.isEmpty)
        #expect(HistoryStore(fileURL: url).events.isEmpty)
    }
}
