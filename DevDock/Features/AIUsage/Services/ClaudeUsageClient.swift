import Foundation

nonisolated enum UsageError: LocalizedError, Sendable {
    case noCredential
    case tokenExpired
    case rateLimited
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noCredential: "Not logged in"
        case .tokenExpired: "Login expired"
        case .rateLimited: "Rate limited, retrying later"
        case .http(let code): "Usage request failed (HTTP \(code))"
        case .badResponse: "Unexpected usage response"
        }
    }
}

/// Reads quota for subscription accounts from the same endpoint Claude Code's `/usage` uses.
///
/// The OAuth token is read from the Keychain item Claude Code maintains, kept in memory
/// for the request only, and never logged or stored. It is never refreshed here: a refresh
/// rotates the token and would log Claude Code out; running `claude-<name>` refreshes it.
nonisolated enum ClaudeUsageClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch(_ info: ClaudeAccountInfo) async throws -> UsageSnapshot {
        let credential = try await readCredential(service: info.keychainService)
        if let expiresAt = credential.expiresAt, expiresAt < .now { throw UsageError.tokenExpired }

        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("DevDock", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: throw UsageError.tokenExpired
        case 429: throw UsageError.rateLimited
        case let code: throw UsageError.http(code)
        }
        return try parse(data, account: info.account, plan: credential.plan)
    }

    // MARK: - Credential

    private struct Credential {
        let accessToken: String
        let expiresAt: Date?
        let plan: String?
    }

    /// Uses `/usr/bin/security`, which Claude Code itself uses to write the item,
    /// so reading it doesn't trigger a Keychain permission prompt.
    private static func readCredential(service: String) async throws -> Credential {
        let result = try await ShellRunner.launch(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", service, "-w"],
            environment: [:], currentDirectory: nil, timeout: .seconds(5)
        )
        guard result.succeeded,
              let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw UsageError.noCredential }

        return Credential(
            accessToken: token,
            expiresAt: (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) },
            plan: (oauth["subscriptionType"] as? String)?.capitalized
        )
    }

    // MARK: - Response

    static func parse(_ data: Data, account: AIAccount, plan: String?) throws -> UsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.badResponse
        }

        // `limits` lists every active quota (session, weekly, per-model weekly …).
        var windows: [UsageWindow] = (json["limits"] as? [[String: Any]] ?? []).compactMap { limit in
            guard let kind = limit["kind"] as? String, let percent = limit["percent"] as? Double else { return nil }
            return UsageWindow(title: title(forKind: kind), used: percent / 100,
                               resetsAt: (limit["resets_at"] as? String).flatMap(ISODate.parse))
        }
        // Older response shape.
        if windows.isEmpty {
            for (key, title) in [("five_hour", "Session"), ("seven_day", "Weekly")] {
                guard let window = json[key] as? [String: Any], let used = window["utilization"] as? Double else { continue }
                windows.append(UsageWindow(title: title, used: used / 100,
                                           resetsAt: (window["resets_at"] as? String).flatMap(ISODate.parse)))
            }
        }
        guard !windows.isEmpty else { throw UsageError.badResponse }

        return UsageSnapshot(account: account, plan: plan, windows: windows,
                             breakdown: breakdown(json["seven_day_breakdown"]),
                             updatedAt: .now, source: .officialAPI)
    }

    /// "session" → "Session", "weekly_all" → "Weekly", "weekly_opus" → "Weekly · Opus".
    private static func title(forKind kind: String) -> String {
        switch kind {
        case "session": return "Session"
        case "weekly_all", "weekly": return "Weekly"
        default:
            let parts = kind.split(separator: "_").map { $0.capitalized }
            return parts.count > 1 ? "\(parts[0]) · \(parts.dropFirst().joined(separator: " "))" : parts.first ?? kind
        }
    }

    /// "Claude Code 81% · Cowork 16% · Chats 3%" — where this week's usage went.
    private static func breakdown(_ value: Any?) -> String? {
        guard let rows = (value as? [String: Any])?["rows"] as? [[String: Any]] else { return nil }
        let parts = rows
            .compactMap { row -> (String, Int)? in
                guard let name = row["display_name"] as? String, let percent = row["percent"] as? Int, percent > 0 else { return nil }
                return (name, percent)
            }
            .sorted { $0.1 > $1.1 }
            .map { "\($0.0) \($0.1)%" }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// ISO 8601 with any number of fractional digits ("…59.845494+00:00", "…31.027Z").
nonisolated enum ISODate {
    static func parse(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
