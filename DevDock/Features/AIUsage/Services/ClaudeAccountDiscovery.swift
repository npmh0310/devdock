import CryptoKit
import Foundation

/// Claude Code account on this Mac: one `CLAUDE_CONFIG_DIR` (`~/.claude`, `~/.claude-personal` …).
nonisolated struct ClaudeAccountInfo: Sendable {
    let account: AIAccount
    let configDir: String
    let email: String?
    /// Keychain service holding the OAuth credential (subscription accounts only).
    let keychainService: String
}

/// Finds Claude Code accounts by their config directories.
nonisolated enum ClaudeAccountDiscovery {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func discover() -> [ClaudeAccountInfo] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: home)) ?? []
        let dirs = names
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .filter { $0 != ".claude-mem" } // claude-mem plugin data, not an account
            .map { "\(home)/\($0)" }
            .filter { dir in
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return false }
                return fm.fileExists(atPath: "\(dir)/settings.json") || fm.fileExists(atPath: configFile(for: dir))
            }

        let aliases = ShellAliases.claudeConfigDirs()
        var accounts = dirs.map { info(for: $0, alias: aliases[$0]) }
        // `~/.claude` is often the same login as a named dir; keep the named one.
        let defaultDir = "\(home)/.claude"
        let namedEmails = Set(accounts.filter { $0.configDir != defaultDir }.compactMap(\.email))
        accounts.removeAll { $0.configDir == defaultDir && $0.email.map(namedEmails.contains) == true }
        // Quota accounts first, gateway accounts (no quota) after.
        return accounts.sorted {
            ($0.account.isGateway ? 1 : 0, $0.account.name) < ($1.account.isGateway ? 1 : 0, $1.account.name)
        }
    }

    private static func info(for dir: String, alias: String?) -> ClaudeAccountInfo {
        let folder = (dir as NSString).lastPathComponent
        let oauth = readJSON(configFile(for: dir))?["oauthAccount"] as? [String: Any]
        let email = oauth?["emailAddress"] as? String
        // `~/.claude-work` → "work"; the plain `~/.claude` is named after its login.
        let name = folder == ".claude"
            ? (email?.split(separator: "@").first.map(String.init) ?? "claude")
            : String(folder.dropFirst(".claude-".count))
        let command = alias ?? (folder == ".claude" ? "claude" : "CLAUDE_CONFIG_DIR=~/\(folder) claude")

        let settings = readJSON("\(dir)/settings.json")
        let env = settings?["env"] as? [String: Any]
        let auth: AIAccount.Auth
        if let base = env?["ANTHROPIC_BASE_URL"] as? String, let host = URL(string: base)?.host {
            auth = .gateway(host: host)
        } else {
            auth = .subscription
        }

        return ClaudeAccountInfo(
            account: AIAccount(id: dir, provider: .claude, name: name, auth: auth, command: command),
            configDir: dir,
            email: email,
            keychainService: keychainService(for: dir)
        )
    }

    /// Claude Code names the item after the first 8 hex chars of sha256(config dir);
    /// the default `~/.claude` has no suffix.
    static func keychainService(for dir: String) -> String {
        guard dir != "\(home)/.claude" else { return "Claude Code-credentials" }
        let digest = SHA256.hash(data: Data(dir.utf8)).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(digest.prefix(8))"
    }

    /// The default account keeps its state in `~/.claude.json`, others inside their dir.
    private static func configFile(for dir: String) -> String {
        dir == "\(home)/.claude" ? "\(home)/.claude.json" : "\(dir)/.claude.json"
    }

    private static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

/// Reads `alias name='CLAUDE_CONFIG_DIR=… claude'` lines from the user's shell startup files,
/// so notices can say "run `claude-work`" instead of the full env-var form.
nonisolated enum ShellAliases {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    private static let files = [".zshrc", ".zprofile", ".zshenv", ".bashrc", ".bash_profile", ".profile"]

    /// Config dir (absolute path) → alias name.
    static func claudeConfigDirs() -> [String: String] {
        files.reduce(into: [:]) { result, file in
            guard let text = try? String(contentsOfFile: "\(home)/\(file)", encoding: .utf8) else { return }
            result.merge(parse(text, home: home)) { first, _ in first }
        }
    }

    static func parse(_ text: String, home: String) -> [String: String] {
        let pattern = #/^\s*alias\s+([\w.-]+)=['"]?.*CLAUDE_CONFIG_DIR=['"]?([^'"\s]+)['"]?\s+claude\b/#
        var result: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let match = try? pattern.firstMatch(in: String(line)) else { continue }
            let dir = String(match.2)
                .replacingOccurrences(of: "${HOME}", with: home)
                .replacingOccurrences(of: "$HOME", with: home)
                .replacingOccurrences(of: "~", with: home)
            if result[dir] == nil { result[dir] = String(match.1) }
        }
        return result
    }
}
