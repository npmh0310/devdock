import Foundation
import Testing
@testable import DevDock

@Suite struct UsagePaceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var resetsAt: Date { now + 3 * 3600 }

    private func sample(_ minutesAgo: Double, _ used: Double, reset: Date? = nil) -> UsageSample {
        UsageSample(date: now - minutesAgo * 60, used: used, resetsAt: reset ?? resetsAt)
    }

    @Test func runsOutBeforeReset() throws {
        // 20% per 30 min, at 60% now: full in 60 min, reset in 3 h.
        let window = UsageWindow(title: "Session", used: 0.6, resetsAt: resetsAt)
        let pace = UsageHistory.pace(samples: [sample(30, 0.4), sample(0, 0.6)], window: window, resetsAt: resetsAt, now: now)
        guard case .runsOut(let at, let before) = pace else { Issue.record("expected runsOut, got \(String(describing: pace))"); return }
        #expect(abs(at.timeIntervalSince(now + 3600)) < 1)
        #expect(abs(before - 2 * 3600) < 1)
    }

    @Test func onTrackProjectsUsageAtReset() {
        // 3% per hour, 10% now, 3 h left: ~19% at reset.
        let window = UsageWindow(title: "Session", used: 0.10, resetsAt: resetsAt)
        let pace = UsageHistory.pace(samples: [sample(60, 0.07), sample(0, 0.10)], window: window, resetsAt: resetsAt, now: now)
        guard case .onTrack(let projected) = pace else { Issue.record("expected onTrack"); return }
        #expect(abs(projected - 0.19) < 0.001)
    }

    @Test func ignoresSamplesFromPreviousWindow() {
        let window = UsageWindow(title: "Session", used: 0.2, resetsAt: resetsAt)
        let old = sample(60, 0.9, reset: now - 600) // last window
        #expect(UsageHistory.pace(samples: [old, sample(0, 0.2)], window: window, resetsAt: resetsAt, now: now) == nil)
    }

    @Test func needsTenMinutesOfHistory() {
        let window = UsageWindow(title: "Session", used: 0.3, resetsAt: resetsAt)
        #expect(UsageHistory.pace(samples: [sample(5, 0.2), sample(0, 0.3)], window: window, resetsAt: resetsAt, now: now) == nil)
    }

    @Test func idleAccountStaysWhereItIs() {
        let window = UsageWindow(title: "Weekly", used: 0.5, resetsAt: resetsAt)
        let pace = UsageHistory.pace(samples: [sample(120, 0.5), sample(0, 0.5)], window: window, resetsAt: resetsAt, now: now)
        #expect(pace == .onTrack(projected: 0.5))
    }

    @Test func toleratesResetTimeDrift() {
        // The API reports 05:59:59.8 one time and 06:00:00.4 the next for the same window.
        let window = UsageWindow(title: "Session", used: 0.5, resetsAt: resetsAt)
        let samples = [sample(30, 0.4, reset: resetsAt - 0.6), sample(0, 0.5)]
        #expect(UsageHistory.pace(samples: samples, window: window, resetsAt: resetsAt, now: now) != nil)
    }
}

@Suite struct ShortLabelTests {
    @Test func usesFirstLetterUnlessItCollides() {
        #expect(AppState.shortLabels(["side", "personal", "Codex"]) == ["S", "P", "C"])
        #expect(AppState.shortLabels(["work", "web", "Codex"]) == ["Wo", "We", "C"])
    }
}
