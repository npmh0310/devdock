import Foundation
import Testing
@testable import DevDock

@Suite struct ProjectsTests {
    private func project(_ name: String, group: String = "personal", parent: String? = nil, minutesAgo: Double? = nil) -> Project {
        Project(id: "/w/\(group)/\(parent.map { "\($0)/" } ?? "")\(name)", name: name, group: group, parent: parent,
                lastActivity: minutesAgo.map { Date.now - $0 * 60 })
    }

    @Test func pinnedFirstThenMostRecent() {
        let a = project("a", minutesAgo: 5), b = project("b", minutesAgo: 1), c = project("c"), d = project("d", minutesAgo: 600)
        let sorted = ProjectRanking.sorted([a, b, c, d], pinned: [d.id])
        #expect(sorted.map(\.name) == ["d", "b", "a", "c"])
    }

    @Test func searchPrefersPrefixThenSubstringThenLettersInOrder() {
        let projects = [project("madison-portal", group: "madison"), project("portal-x"), project("gl-docs", group: "madison"),
                        project("ai-daily-fe")]
        #expect(ProjectRanking.search(projects, query: "port").map(\.name) == ["portal-x", "madison-portal"])
        // Initials beat a substring elsewhere ("exa-mp-le").
        let withExample = projects + [project("rag-example")]
        #expect(ProjectRanking.search(withExample, query: "mp").first?.name == "madison-portal")
        // The group matches too: every madison project.
        #expect(Set(ProjectRanking.search(projects, query: "madison").map(\.name)) == ["madison-portal", "gl-docs"])
        #expect(ProjectRanking.search(projects, query: "zzz").isEmpty)
    }

    @Test func nestedRepoMatchesByParent() {
        let boidat = project("boidat", group: "start-up", parent: "tium-power")
        #expect(ProjectRanking.search([boidat, project("devdock")], query: "tium").map(\.name) == ["boidat"])
    }

    @Test func encodesPathsLikeClaudeCode() {
        #expect(ProjectScanner.encode("/Users/me/workspace/start-up/g.news") == "-Users-me-workspace-start-up-g-news")
    }

    @Test func scansGroupsProjectsAndNestedRepos() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("projects-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fm = FileManager.default
        for dir in ["madison/portal/.git", "start-up/tium-power/boidat/.git", "start-up/tium-power/node_modules/x/.git",
                    "start-up/tium-power/docs", ".hidden/x"] {
            try fm.createDirectory(atPath: "\(root)/\(dir)", withIntermediateDirectories: true)
        }
        try Data().write(to: URL(fileURLWithPath: "\(root)/madison/README.md"))

        let projects = ProjectScanner.folders(root: root)
        #expect(projects.map(\.name) == ["portal", "tium-power", "boidat"])
        #expect(projects.last?.parent == "tium-power")
        #expect(projects.last?.group == "start-up")
    }

    @Test func quotesPathsForShellAndAppleScript() {
        #expect(TerminalLauncher.shellQuoted("/w/it's") == #"'/w/it'\''s'"#)
        #expect(TerminalLauncher.appleScriptString(#"say "hi" \ ok"#) == #""say \"hi\" \\ ok""#)
    }
}
