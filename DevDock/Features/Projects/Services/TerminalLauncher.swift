import AppKit

/// Opens a folder in a new iTerm tab (a new window when iTerm has none).
/// Without iTerm, falls back to the first installed terminal.
enum TerminalLauncher {
    private static let iTerm = "com.googlecode.iterm2"

    static func openTab(at path: String) async {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTerm) != nil else {
            return Launcher.openInTerminal(path)
        }
        // osascript, not NSAppleScript: runs off the main thread. Long timeout because the
        // first run waits on the Automation permission prompt.
        let result = try? await ShellRunner.run("/usr/bin/osascript", arguments: ["-e", script(for: path)], timeout: .seconds(120))
        // Automation refused (Privacy & Security → Automation) or iTerm hung: still get there.
        if result?.succeeded != true { Launcher.openInTerminal(path) }
    }

    static func script(for path: String) -> String {
        let command = appleScriptString("cd \(shellQuoted(path)) && clear")
        return """
        tell application id "\(iTerm)"
            activate
            if (count of windows) = 0 then
                set newWindow to (create window with default profile)
                tell current session of newWindow to write text \(command)
            else
                tell current window
                    create tab with default profile
                    tell current session to write text \(command)
                end tell
            end if
        end tell
        """
    }

    /// 'it'\''s' for the shell.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A double-quoted AppleScript literal.
    static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
