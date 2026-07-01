import Foundation
import Combine

@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var ports: [PortInfo] = []

    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let scanned = PortScanner.scan().sorted { $0.port < $1.port }
        ports = scanned
    }

    func kill(_ info: PortInfo) {
        Darwin.kill(info.pid, SIGTERM)
        // Give the process a moment to exit, then refresh.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }
}
