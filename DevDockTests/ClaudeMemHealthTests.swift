import Foundation
import Testing
@testable import DevDock

@Suite struct ClaudeMemHealthTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func healthy() -> ClaudeMemSignals {
        var s = ClaudeMemSignals()
        s.isInstalled = true
        s.provider = "openai-compatible"
        s.model = "deepseek-chat"
        s.worker = .init(pid: 1, port: 37701, startedAt: now - 3600, version: "13.35.0", isResponding: true)
        s.lastObservation = now - 120
        s.lastActivity = now - 60
        return s
    }

    @Test func okWhenSavingWhileWorking() {
        let a = ClaudeMemHealth.assess(healthy(), now: now)
        #expect(a.status == .ok)
        #expect(a.summary == "Saved 2m ago")
    }

    @Test func downWhenWorkerGoneOrSilent() {
        var s = healthy()
        s.worker = nil
        #expect(ClaudeMemHealth.assess(s, now: now).status == .down)
        s = healthy()
        s.worker?.isResponding = false
        #expect(ClaudeMemHealth.assess(s, now: now).summary == "Worker is not responding")
    }

    @Test func oneFailureLagsThreeOrTenMinutesStop() {
        var s = healthy()
        s.consecutiveFailures = 1
        s.failingSince = now - 60
        s.lastError = .init(date: now - 60, message: "timeout", kind: "transient", code: nil, action: "Raise the timeout", provider: nil)
        let lagging = ClaudeMemHealth.assess(s, now: now)
        #expect(lagging.status == .lagging)
        #expect(lagging.fix == "Raise the timeout")

        s.failingSince = now - 11 * 60
        #expect(ClaudeMemHealth.assess(s, now: now).status == .down)
        s.failingSince = now - 60
        s.consecutiveFailures = 3
        #expect(ClaudeMemHealth.assess(s, now: now).status == .down)
    }

    @Test func lagsOnlyWhenWorkingLongAfterTheLastSave() {
        var s = healthy()
        // Idle for hours: nothing to save, not a problem.
        s.lastObservation = now - 5 * 3600
        s.lastActivity = now - 4 * 3600
        #expect(ClaudeMemHealth.assess(s, now: now).status == .ok)
        // Just started working again: not yet.
        s.lastActivity = now - 60
        s.lastObservation = now - 10 * 60
        #expect(ClaudeMemHealth.assess(s, now: now).status == .ok)
        // Working, and 40 minutes since anything was saved.
        s.lastObservation = now - 40 * 60
        #expect(ClaudeMemHealth.assess(s, now: now).status == .lagging)
    }

    @Test func outOfCreditAndCooldownStop() {
        var s = healthy()
        s.outOfCredit = true
        #expect(ClaudeMemHealth.assess(s, now: now).summary == "DeepSeek balance used up")
        s = healthy()
        s.cooldown = "codex five_hour quota cooldown"
        #expect(ClaudeMemHealth.assess(s, now: now).status == .down)
    }

    @Test func notInstalledIsQuiet() {
        #expect(ClaudeMemHealth.assess(ClaudeMemSignals(), now: now).status == .ok)
    }
}
