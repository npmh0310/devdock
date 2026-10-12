import Foundation
import Observation

/// Runs registered refresh jobs on an interval while the panel is open.
/// Stopped while the panel is closed, so the app stays idle in the background.
/// Each job decides for itself whether it is due; `force` (the refresh button) skips that.
@Observable
final class RefreshScheduler {
    private(set) var isRefreshing = false
    private(set) var lastRefreshed: Date?

    @ObservationIgnored private var jobs: [(_ force: Bool) async -> Void] = []
    @ObservationIgnored private var loop: Task<Void, Never>?

    func register(_ job: @escaping (_ force: Bool) async -> Void) {
        jobs.append(job)
    }

    func start(every interval: Duration) {
        stop()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func refreshNow(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let started = ContinuousClock.now
        // Jobs interleave while they await, so a slow network fetch doesn't hold up the port scan.
        let running = jobs.map { job in Task { await job(force) } }
        for task in running { await task.value }
        // A manual refresh can finish in a few ms; keep the spinner long enough to be seen.
        if force { try? await Task.sleep(until: started + .milliseconds(600)) }
        lastRefreshed = .now
        isRefreshing = false
    }
}
