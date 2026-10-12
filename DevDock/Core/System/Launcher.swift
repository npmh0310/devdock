import AppKit

/// Opens folders and URLs in the user's tools.
/// Preferred IDE/terminal become settings in M4; until then the first installed one wins.
enum Launcher {
    private static let editors = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed"] // VS Code, Cursor, Zed
    private static let shortNames = ["com.microsoft.VSCode": "VS Code", "com.todesktop.230313mzl4w4u92": "Cursor", "dev.zed.Zed": "Zed"]
    private static let terminals = ["com.mitchellh.ghostty", "com.googlecode.iterm2", "com.apple.Terminal"]

    static var editorName: String {
        editors.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
            .flatMap { shortNames[$0] } ?? "Editor"
    }

    static func openInEditor(_ path: String) { open(path, withFirstOf: editors) }
    static func openInTerminal(_ path: String) { open(path, withFirstOf: terminals) }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    static func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// "~/workspace/app" instead of "/Users/me/workspace/app".
    static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private static func open(_ path: String, withFirstOf bundleIDs: [String]) {
        guard let app = bundleIDs.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first else {
            revealInFinder(path)
            return
        }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
