import Darwin
import Foundation
import Observation

/// Current listeners plus the actions that change them.
@Observable
final class PortsStore {
    private(set) var ports: [ListeningPort] = []
    private(set) var errorMessage: String?
    private(set) var hasLoaded = false

    func refresh() async {
        do {
            ports = try await PortScanner.scan()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoaded = true
    }

    /// SIGTERM first so dev servers can shut down cleanly; `force` sends SIGKILL.
    @discardableResult
    func kill(_ port: ListeningPort, force: Bool = false) async -> Bool {
        guard port.isOwnedByCurrentUser else { return false }
        let sent = Darwin.kill(port.pid, force ? SIGKILL : SIGTERM) == 0
        // Give the process a moment to release the socket before rescanning.
        try? await Task.sleep(for: .milliseconds(600))
        await refresh()
        return sent
    }

    func port(id: ListeningPort.ID) -> ListeningPort? {
        ports.first { $0.id == id }
    }
}
