import Foundation
import Observation

/// claude-mem's health. Everything is local (files, a localhost request), so it
/// refreshes on every tick without throttling.
@Observable
final class ClaudeMemStore {
    private(set) var signals = ClaudeMemSignals()
    private(set) var assessment = ClaudeMemAssessment(status: .ok, summary: "Checking…")
    private(set) var updatedAt: Date?

    @ObservationIgnored var onUpdate: (() -> Void)?
    /// Whether the provider it runs on ran out of prepaid credit; set by AppState.
    @ObservationIgnored var outOfCredit: () -> Bool = { false }
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    var isInstalled: Bool { signals.isInstalled }

    func refresh() async {
        if let inFlight { return await inFlight.value }
        let task = Task {
            let signals = await ClaudeMemHealth.read(outOfCredit: outOfCredit())
            self.signals = signals
            assessment = ClaudeMemHealth.assess(signals)
            updatedAt = .now
            onUpdate?()
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    var logURL: URL {
        let day = Date.now.formatted(.iso8601.year().month().day())
        return URL(fileURLWithPath: "\(ClaudeMemFiles.home)/logs/claude-mem-\(day).log")
    }

    var settingsPath: String { "\(ClaudeMemFiles.home)/settings.json" }

    var viewerURL: URL? {
        signals.worker.flatMap { URL(string: "http://127.0.0.1:\($0.port)/") }
    }
}
