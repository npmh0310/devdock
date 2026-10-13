import Foundation

/// A folder the user works in: `~/workspace/<group>/<name>`, or a git repo nested
/// one or two levels inside one (`start-up/tium-power/boidat`).
nonisolated struct Project: Identifiable, Hashable, Sendable {
    /// Absolute path.
    let id: String
    let name: String
    /// First folder under the root: "madison", "personal".
    let group: String
    /// Folders between the group and the project, for nested repos: "tium-power".
    var parent: String?
    /// Latest of: opened from DevDock, a Claude Code session in it, a git commit or checkout.
    var lastActivity: Date?

    var path: String { id }
}

nonisolated enum ProjectScanner {
    static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("workspace").path
    /// Never descended into when looking for nested repos.
    private static let skipped: Set<String> = ["node_modules", "build", "dist", "vendor", "Pods", "target", "out"]

    static func scan(root: String = root, opened: [String: Date] = [:]) -> [Project] {
        var projects = folders(root: root)
        let sessions = claudeSessions()
        for index in projects.indices {
            let path = projects[index].path
            projects[index].lastActivity = [opened[path], gitActivity(path)].compactMap { $0 }.max()
        }
        // Each transcript folder belongs to the deepest project whose path it starts with.
        let encoded = projects.map { encode($0.path) }
        for (folder, date) in sessions {
            let match = encoded.indices
                .filter { folder == encoded[$0] || folder.hasPrefix(encoded[$0] + "-") }
                .max { encoded[$0].count < encoded[$1].count }
            if let match, date > (projects[match].lastActivity ?? .distantPast) {
                projects[match].lastActivity = date
            }
        }
        return projects
    }

    // MARK: - Folders

    static func folders(root: String) -> [Project] {
        var projects: [Project] = []
        for group in directories(in: root) {
            for name in directories(in: "\(root)/\(group)") {
                let path = "\(root)/\(group)/\(name)"
                projects.append(Project(id: path, name: name, group: group))
                // A folder that is not a repo itself is often a set of repos.
                guard !isRepo(path) else { continue }
                for repo in nestedRepos(in: path, depth: 2) {
                    let relative = String(repo.dropFirst(path.count + 1))
                    let parts = relative.split(separator: "/").map(String.init)
                    let parent = ([name] + parts.dropLast()).joined(separator: "/")
                    projects.append(Project(id: repo, name: parts.last ?? relative, group: group, parent: parent))
                }
            }
        }
        return projects
    }

    private static func nestedRepos(in path: String, depth: Int) -> [String] {
        guard depth > 0 else { return [] }
        return directories(in: path).filter { !skipped.contains($0) }.flatMap { child -> [String] in
            let childPath = "\(path)/\(child)"
            return isRepo(childPath) ? [childPath] : nestedRepos(in: childPath, depth: depth - 1)
        }
    }

    /// Visible subdirectories, sorted by name.
    private static func directories(in path: String) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: path)) ?? [])
            .filter { name in
                var isDirectory: ObjCBool = false
                return !name.hasPrefix(".") && fm.fileExists(atPath: "\(path)/\(name)", isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func isRepo(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: "\(path)/.git")
    }

    // MARK: - Activity

    /// `.git/logs/HEAD` changes on every commit, checkout and pull.
    private static func gitActivity(_ path: String) -> Date? {
        modified("\(path)/.git/logs/HEAD")
    }

    /// Newest transcript per Claude Code project folder, across every `~/.claude*` account.
    static func claudeSessions() -> [String: Date] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var newest: [String: Date] = [:]
        let configs = ((try? fm.contentsOfDirectory(atPath: home)) ?? []).filter { $0.hasPrefix(".claude") && $0 != ".claude-mem" }
        for config in configs {
            let projects = "\(home)/\(config)/projects"
            for folder in (try? fm.contentsOfDirectory(atPath: projects)) ?? [] {
                let dir = "\(projects)/\(folder)"
                for file in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where file.hasSuffix(".jsonl") {
                    if let date = modified("\(dir)/\(file)"), date > (newest[folder] ?? .distantPast) {
                        newest[folder] = date
                    }
                }
            }
        }
        return newest
    }

    /// How Claude Code names a project folder: every character but letters and digits becomes "-".
    static func encode(_ path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    private static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}

/// Order and search. Pinned first, then most recent work; a query ranks by how well it matches.
nonisolated enum ProjectRanking {
    static func sorted(_ projects: [Project], pinned: [String]) -> [Project] {
        let pinOrder = Dictionary(uniqueKeysWithValues: pinned.enumerated().map { ($1, $0) })
        return projects.sorted { a, b in
            switch (pinOrder[a.id], pinOrder[b.id]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return recency(a, b)
            }
        }
    }

    static func search(_ projects: [Project], query: String) -> [Project] {
        let q = query.lowercased().filter { !$0.isWhitespace }
        guard !q.isEmpty else { return projects }
        return projects
            .compactMap { project in score(project, q).map { (project, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : recency($0.0, $1.0) }
            .map(\.0)
    }

    /// Prefix of the name beats word initials beats a substring beats letters in order;
    /// the group and parent folders count too, a little less.
    static func score(_ project: Project, _ q: String) -> Int? {
        let name = project.name.lowercased()
        if name.hasPrefix(q) { return 4000 - name.count }
        // First letters of each word: "mp" → madison-portal.
        let initials = String(name.split(whereSeparator: { "-_. ".contains($0) }).compactMap(\.first))
        if q.count > 1, initials.hasPrefix(q) { return 3500 - initials.count }
        if let range = name.range(of: q) { return 3000 - name.distance(from: name.startIndex, to: range.lowerBound) }
        if let gaps = subsequenceGaps(q, in: name) { return 2000 - gaps }
        let full = [project.group, project.parent, project.name].compactMap { $0?.lowercased() }.joined(separator: " ")
        if full.contains(q) { return 1500 }
        if let gaps = subsequenceGaps(q, in: full) { return 1000 - gaps }
        return nil
    }

    /// Letters skipped to find `q` in order inside `text`, or nil when it isn't there.
    private static func subsequenceGaps(_ q: String, in text: String) -> Int? {
        var gaps = 0
        var remaining = q[...]
        for character in text {
            guard let next = remaining.first else { break }
            if character == next { remaining = remaining.dropFirst() } else if remaining.count < q.count { gaps += 1 }
        }
        return remaining.isEmpty ? gaps : nil
    }

    private static func recency(_ a: Project, _ b: Project) -> Bool {
        switch (a.lastActivity, b.lastActivity) {
        case let (x?, y?): return x > y
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
