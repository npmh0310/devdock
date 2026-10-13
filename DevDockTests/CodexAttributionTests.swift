import Foundation
import Testing
@testable import DevDock

@Suite struct CodexAttributionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let length: TimeInterval = 5 * 3600
    /// Window started 2 h ago.
    var resetsAt: Date { now + 3 * 3600 }
    var start: Date { resetsAt - length }

    private func reading(_ minutesIn: Double, _ used: Double, _ client: String = "VS Code") -> (date: Date, used: Double, client: String) {
        (start + minutesIn * 60, used, client)
    }

    private func attribute(used: Double, _ readings: [(date: Date, used: Double, client: String)], claudeMem: [Double] = []) -> QuotaAttribution? {
        CodexAttribution.attribute(window: UsageWindow(title: "Session", used: used, resetsAt: resetsAt), length: length,
                                   readings: readings, claudeMemRequests: claudeMem.map { start + $0 * 60 }, now: now)
    }

    @Test func steadySessionIsAllYours() throws {
        let result = try #require(attribute(used: 0.30, [reading(1, 0.05), reading(5, 0.15), reading(9, 0.30)]))
        #expect(result.parts == [.init(source: .client("VS Code"), used: 0.30)])
    }

    @Test func riseAfterLastReadingGoesToClaudeMemWhenItWasRunning() throws {
        let result = try #require(attribute(used: 1.0, [reading(1, 0.10), reading(5, 0.20)], claudeMem: [60, 70, 90]))
        #expect(abs(result.used(by: .claudeMem) - 0.80) < 1e-9)
        #expect(abs(result.used(by: .client("VS Code")) - 0.20) < 1e-9)
        #expect(result.claudeMemRequests == 3)
        #expect(result.used(by: .unknown) == 0)
    }

    @Test func riseAcrossIdleGapWithNothingRunningIsUnknown() throws {
        // Idle from minute 5 to 65 with nothing on this Mac calling Codex, yet +40%.
        let result = try #require(attribute(used: 0.65, [reading(1, 0.10), reading(5, 0.20), reading(65, 0.60), reading(66, 0.65)]))
        #expect(abs(result.used(by: .unknown) - 0.40) < 1e-9)
        #expect(abs(result.used(by: .client("VS Code")) - 0.25) < 1e-9)
    }

    @Test func splitsBetweenClients() throws {
        let result = try #require(attribute(used: 0.30, [reading(1, 0.10, "VS Code"), reading(30, 0.15, "CLI"), reading(32, 0.30, "CLI")],
                                            claudeMem: [10]))
        // VS Code 10%, claude-mem 5% (gap 1→30 with claude-mem running), CLI 15%.
        #expect(result.parts.map(\.source) == [.client("CLI"), .client("VS Code"), .claudeMem])
    }

    @Test func noAttributionAfterReset() {
        let window = UsageWindow(title: "Session", used: 0.5, resetsAt: now - 60)
        #expect(CodexAttribution.attribute(window: window, length: length, readings: [], claudeMemRequests: [], now: now) == nil)
    }

    @Test func clientNames() {
        #expect(CodexQuotaLog.clientName("codex_vscode") == "VS Code")
        #expect(CodexQuotaLog.clientName("codex_sdk_ts") == "SDK")
        #expect(CodexQuotaLog.clientName("codex_desktop") == "desktop")
    }
}

@Suite struct CodexLogSnapshotTests {
    @Test func readingBecomesSnapshotAndResetWindowsStartAtZero() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reading = CodexQuotaReading(date: now - 600, client: "CLI", session: 0.4, sessionResetsAt: now - 60,
                                        weekly: 0.3, weeklyResetsAt: now + 86400)
        let snapshot = CodexUsageClient.snapshot(from: reading, plan: "Plus", now: now)
        #expect(snapshot.windows.map(\.title) == ["Session", "Weekly"])
        #expect(snapshot.windows.map(\.used) == [0, 0.3])
        #expect(snapshot.plan == "Plus")
        #expect(snapshot.updatedAt == now - 600)
        #expect(snapshot.source == .localLogs)
    }
}
