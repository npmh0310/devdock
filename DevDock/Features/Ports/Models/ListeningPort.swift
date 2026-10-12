import Foundation

/// A process listening on a TCP port, merged across IPv4/IPv6 sockets.
nonisolated struct ListeningPort: Identifiable, Hashable, Sendable {
    enum Category: Int, Comparable, Sendable {
        /// Runs from a project folder: dev servers, APIs …
        case project
        /// Homebrew-installed daemons: postgres, mysql, redis …
        case service
        /// Desktop apps and system agents. Hidden unless "Show all" is on.
        case other

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let port: Int
    let pid: Int32
    /// Short name, e.g. "node", "next-server (v16.2.10)", "postgres".
    let processName: String
    let uid: uid_t
    /// Bound addresses, e.g. ["127.0.0.1", "[::1]"] or ["*"].
    let addresses: [String]
    var category: Category = .other
    var project: ProjectInfo?
    var executable: String?
    var command: String?
    var workingDirectory: String?
    var elapsed: TimeInterval?
    var memoryBytes: Int64?
    var cpuPercent: Double?

    var id: String { "\(pid):\(port)" }
    var url: URL { URL(string: "http://localhost:\(port)")! }

    /// Reachable from other machines on the network, not only from this Mac.
    var isExposed: Bool { addresses.contains { $0 == "*" || $0 == "0.0.0.0" || $0 == "[::]" } }

    var isOwnedByCurrentUser: Bool { uid == getuid() }

    /// Project name, or the process name when the port doesn't belong to a project.
    var displayName: String { project?.name ?? processName }
}

/// The project a process was started from.
nonisolated struct ProjectInfo: Hashable, Sendable {
    /// Repository name, e.g. "my-app".
    let name: String
    /// Repository root, or the package folder when there is no git repo.
    let root: String
    /// Package folder inside a monorepo, e.g. "apps/web". Nil at the root.
    var subpath: String?
    var branch: String?
    /// "Next.js", "Vite", "FastAPI" …
    var framework: String?

    /// Folder the server actually runs from.
    var packagePath: String {
        guard let subpath else { return root }
        return (root as NSString).appendingPathComponent(subpath)
    }
}
