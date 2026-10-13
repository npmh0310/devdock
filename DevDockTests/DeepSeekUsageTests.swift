import Foundation
import Testing
@testable import DevDock

@Suite struct DeepSeekUsageTests {
    @Test func parsesBalancePreferringUSD() throws {
        let json = """
        {"is_available": true, "balance_infos": [
          {"currency": "CNY", "total_balance": "30.00", "granted_balance": "0.00", "topped_up_balance": "30.00"},
          {"currency": "USD", "total_balance": "4.25", "granted_balance": "0.25", "topped_up_balance": "4.00"}
        ]}
        """
        let balance = try DeepSeekUsageClient.parseBalance(Data(json.utf8))
        #expect(balance == Balance(currency: "USD", total: 4.25, granted: 0.25, toppedUp: 4, isAvailable: true))
    }

    @Test func rejectsResponseWithoutBalance() {
        #expect(throws: UsageError.self) { try DeepSeekUsageClient.parseBalance(Data(#"{"error": "x"}"#.utf8)) }
    }

    @Test func parsesEnvFile() {
        let env = ClaudeMemFiles.parseEnv("""
        # comment
        export OPENAI_COMPAT_API_KEY="sk-abc"
        OTHER = 'quoted value'
        BROKEN
        """)
        #expect(env == ["OPENAI_COMPAT_API_KEY": "sk-abc", "OTHER": "quoted value"])
    }

    @Test func spendIgnoresTopUps() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let readings = [5.0, 4.5, 4.0, 14.0, 13.5].enumerated().map {
            BalanceLog.Reading(date: start + Double($0.offset) * 3600, total: $0.element)
        }
        // Since before the second reading: 4.5 → 4.0, top-up, 14 → 13.5.
        #expect(BalanceLog.spent(readings, since: start + 3600) == 1.0)
        // Before the first reading: counted from the first one.
        #expect(BalanceLog.spent(readings, since: start - 86400) == 1.5)
        #expect(BalanceLog.spent([], since: start) == nil)
    }
}

@Suite struct DeepSeekBalanceWindowTests {
    private func readings(_ totals: [Double]) -> [BalanceLog.Reading] {
        totals.enumerated().map { BalanceLog.Reading(date: Date(timeIntervalSince1970: Double($0.offset) * 3600), total: $0.element) }
    }

    @Test func referenceIsBalanceAfterLastTopUp() {
        #expect(BalanceLog.reference(readings([5, 4, 3])) == 5)
        #expect(BalanceLog.reference(readings([5, 1, 11, 10])) == 11)
        #expect(BalanceLog.reference([]) == nil)
    }

    @Test func balanceAsQuota() {
        let balance = Balance(currency: "USD", total: 1.5, granted: 0, toppedUp: 1.5, isAvailable: true)
        #expect(abs(DeepSeekUsageClient.window(balance, reference: 10).used - 0.85) < 1e-9)
        #expect(DeepSeekUsageClient.window(balance, reference: nil).used == 0)
        let empty = Balance(currency: "USD", total: 0, granted: 0, toppedUp: 0, isAvailable: false)
        #expect(DeepSeekUsageClient.window(empty, reference: 10).used == 1)
    }
}
