import Foundation

/// Lists TCP listeners with `lsof`, then enriches them with `ps` and the project resolver.
/// Three short commands per scan (~50 ms), only while the panel is open.
nonisolated enum PortScanner {
    static func scan() async throws -> [ListeningPort] {
        let listing = try await ShellRunner.run("/usr/sbin/lsof", arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcun"])
        // lsof exits 1 when nothing matches; that's an empty list, not an error.
        var ports = parseListeners(listing.stdout)
        guard !ports.isEmpty else { return [] }

        let pids = Set(ports.map(\.pid)).map(String.init).joined(separator: ",")
        async let processes = processInfo(pids: pids)
        async let commands = commandLines(pids: pids)
        async let directories = workingDirectories(pids: pids)
        let (info, cmds, dirs) = try await (processes, commands, directories)

        for index in ports.indices {
            let pid = ports[index].pid
            if let process = info[pid] {
                ports[index].executable = process.executable
                ports[index].elapsed = process.elapsed
                ports[index].memoryBytes = process.rssKB * 1024
                ports[index].cpuPercent = process.cpu
            }
            ports[index].command = cmds[pid]
            ports[index].workingDirectory = dirs[pid]
            ports[index].project = ProjectResolver.resolve(directory: dirs[pid], command: cmds[pid])
            ports[index].category = category(of: ports[index])
        }
        return ports.sorted {
            ($0.category, $0.displayName.lowercased(), $0.port) < ($1.category, $1.displayName.lowercased(), $1.port)
        }
    }

    // MARK: - lsof

    /// `-F pcun` prints one field per line: p<pid>, c<command>, u<uid>, f<fd>, n<addr:port>.
    static func parseListeners(_ output: String) -> [ListeningPort] {
        struct Key: Hashable { let pid: Int32; let port: Int }
        var order: [Key] = []
        var merged: [Key: (name: String, uid: uid_t, addresses: [String])] = [:]

        var pid: Int32 = 0
        var name = ""
        var uid: uid_t = 0
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": name = value
            case "u": uid = uid_t(value) ?? 0
            case "n":
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                let address = String(value[..<colon])
                let key = Key(pid: pid, port: port)
                if merged[key] == nil {
                    order.append(key)
                    merged[key] = (name, uid, [])
                }
                if !merged[key]!.addresses.contains(address) { merged[key]!.addresses.append(address) }
            default: break
            }
        }
        return order.map { key in
            let entry = merged[key]!
            return ListeningPort(port: key.port, pid: key.pid, processName: entry.name, uid: entry.uid, addresses: entry.addresses)
        }
    }

    private static func workingDirectories(pids: String) async throws -> [Int32: String] {
        let result = try await ShellRunner.run("/usr/sbin/lsof", arguments: ["-a", "-p", pids, "-d", "cwd", "-F", "pn"])
        var dirs: [Int32: String] = [:]
        var pid: Int32 = 0
        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("p") { pid = Int32(line.dropFirst()) ?? 0 }
            if line.hasPrefix("n") { dirs[pid] = String(line.dropFirst()) }
        }
        return dirs
    }

    // MARK: - ps

    private struct ProcessInfo {
        let rssKB: Int64
        let cpu: Double
        let elapsed: TimeInterval?
        let executable: String
    }

    private static func processInfo(pids: String) async throws -> [Int32: ProcessInfo] {
        // `comm` goes last because it may contain spaces.
        let result = try await ShellRunner.run("/bin/ps", arguments: ["-o", "pid=,rss=,%cpu=,etime=,comm=", "-p", pids])
        var info: [Int32: ProcessInfo] = [:]
        for line in result.stdout.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5, let pid = Int32(fields[0]) else { continue }
            info[pid] = ProcessInfo(
                rssKB: Int64(fields[1]) ?? 0,
                cpu: Double(fields[2]) ?? 0,
                elapsed: parseElapsed(String(fields[3])),
                executable: String(fields[4])
            )
        }
        return info
    }

    private static func commandLines(pids: String) async throws -> [Int32: String] {
        let result = try await ShellRunner.run("/bin/ps", arguments: ["-ww", "-o", "pid=,command=", "-p", pids])
        var commands: [Int32: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard fields.count == 2, let pid = Int32(fields[0]) else { continue }
            commands[pid] = String(fields[1])
        }
        return commands
    }

    /// `ps` etime: "[[dd-]hh:]mm:ss".
    static func parseElapsed(_ text: String) -> TimeInterval? {
        let dayParts = text.split(separator: "-")
        let days = dayParts.count == 2 ? Double(dayParts[0]) ?? 0 : 0
        let clock = (dayParts.last ?? "").split(separator: ":").compactMap { Double($0) }
        guard !clock.isEmpty else { return nil }
        let seconds = clock.reversed().enumerated().reduce(0.0) { $0 + $1.element * pow(60, Double($1.offset)) }
        return days * 86400 + seconds
    }

    // MARK: - Classification

    private static func category(of port: ListeningPort) -> ListeningPort.Category {
        if port.project != nil { return .project }
        let paths = [port.executable, port.workingDirectory].compactMap { $0 }
        if paths.contains(where: { $0.hasPrefix("/opt/homebrew/") || $0.hasPrefix("/usr/local/") }) {
            return .service
        }
        return .other
    }
}
