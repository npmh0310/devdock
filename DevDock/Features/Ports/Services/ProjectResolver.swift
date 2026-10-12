import Foundation

/// Finds the project a process belongs to by walking up from its working directory.
nonisolated enum ProjectResolver {
    private static let markers = [
        "package.json", "go.mod", "Cargo.toml", "pyproject.toml", "requirements.txt",
        "pom.xml", "build.gradle", "build.gradle.kts", "Gemfile", "composer.json", "mix.exs",
    ]
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// `directory` is the process cwd; `command` is used as a fallback when the cwd
    /// says nothing (e.g. `node /path/to/server.js` started from `/`).
    static func resolve(directory: String?, command: String?) -> ProjectInfo? {
        if let directory, let info = resolveFolder(directory, command: command ?? "") {
            return info
        }
        for path in absolutePaths(in: command ?? "") {
            let dir = (path as NSString).deletingLastPathComponent
            if let info = resolveFolder(dir, command: command ?? "") { return info }
        }
        return nil
    }

    private static func resolveFolder(_ directory: String, command: String) -> ProjectInfo? {
        // Only folders inside home count; ~/Library and dot-folders hold app data, not projects.
        guard directory.hasPrefix(home + "/") else { return nil }
        let relative = directory.dropFirst(home.count + 1)
        if relative.hasPrefix("Library/") || relative.hasPrefix(".") { return nil }

        let fm = FileManager.default
        var packageDir: String?
        var repoRoot: String?
        var dir = directory
        while dir.count > home.count {
            if packageDir == nil, markers.contains(where: { fm.fileExists(atPath: "\(dir)/\($0)") }) {
                packageDir = dir
            }
            if fm.fileExists(atPath: "\(dir)/.git") {
                repoRoot = dir
                break
            }
            dir = (dir as NSString).deletingLastPathComponent
        }

        guard let root = repoRoot ?? packageDir else { return nil }
        let package = packageDir ?? root
        let subpath = package.count > root.count ? String(package.dropFirst(root.count + 1)) : nil

        return ProjectInfo(
            name: (root as NSString).lastPathComponent,
            root: root,
            subpath: subpath,
            branch: repoRoot.flatMap(gitBranch),
            framework: framework(packageDir: package, command: command)
        )
    }

    /// Reads `.git/HEAD` directly; also handles worktrees where `.git` is a file.
    static func gitBranch(repoRoot: String) -> String? {
        var gitDir = "\(repoRoot)/.git"
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: gitDir, isDirectory: &isDirectory)
        if !isDirectory.boolValue {
            guard let pointer = try? String(contentsOfFile: gitDir, encoding: .utf8),
                  pointer.hasPrefix("gitdir:") else { return nil }
            let path = pointer.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            gitDir = path.hasPrefix("/") ? path : "\(repoRoot)/\(path)"
        }
        guard let head = try? String(contentsOfFile: "\(gitDir)/HEAD", encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst("ref: refs/heads/".count)) }
        return String(head.prefix(7)) // detached HEAD
    }

    private static func framework(packageDir: String, command: String) -> String? {
        let cmd = command.lowercased()
        let byCommand: [(String, String)] = [
            ("next-server", "Next.js"), ("next dev", "Next.js"), ("vite", "Vite"), ("nuxt", "Nuxt"),
            ("astro", "Astro"), ("uvicorn", "Uvicorn"), ("gunicorn", "Gunicorn"),
            ("manage.py runserver", "Django"), ("flask", "Flask"), ("rails", "Rails"),
        ]
        if let match = byCommand.first(where: { cmd.contains($0.0) }) { return match.1 }

        guard let data = FileManager.default.contents(atPath: "\(packageDir)/package.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let deps = ((json["dependencies"] as? [String: Any]) ?? [:])
            .merging((json["devDependencies"] as? [String: Any]) ?? [:]) { a, _ in a }
        let byDependency: [(String, String)] = [
            ("next", "Next.js"), ("nuxt", "Nuxt"), ("@remix-run/dev", "Remix"), ("astro", "Astro"),
            ("@nestjs/core", "NestJS"), ("vite", "Vite"), ("fastify", "Fastify"), ("express", "Express"),
        ]
        return byDependency.first { deps[$0.0] != nil }?.1
    }

    private static func absolutePaths(in command: String) -> [String] {
        command.split(separator: " ").map(String.init).filter { $0.hasPrefix(home + "/") }
    }
}
