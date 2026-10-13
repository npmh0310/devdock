import Defaults
import Foundation
import Observation

/// Projects under `~/workspace`, ordered by pins and recent work.
@Observable
final class ProjectsStore {
    private(set) var projects: [Project] = []
    private(set) var hasLoaded = false

    func refresh() async {
        let opened = Defaults[.projectOpens]
        projects = await Task.detached { ProjectScanner.scan(opened: opened) }.value
        hasLoaded = true
    }

    func open(_ project: Project) {
        Task { await TerminalLauncher.openTab(at: project.path) }
        Defaults[.projectOpens][project.path] = .now
        // Keep the history to folders that still exist.
        let known = Set(projects.map(\.path))
        Defaults[.projectOpens] = Defaults[.projectOpens].filter { known.contains($0.key) }
        if let index = projects.firstIndex(of: project) { projects[index].lastActivity = .now }
    }

    func isPinned(_ project: Project) -> Bool {
        Defaults[.pinnedProjects].contains(project.path)
    }

    func togglePin(_ project: Project) {
        if isPinned(project) {
            Defaults[.pinnedProjects].removeAll { $0 == project.path }
        } else {
            Defaults[.pinnedProjects].append(project.path)
        }
    }
}
