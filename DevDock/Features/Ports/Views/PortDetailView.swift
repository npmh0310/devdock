import SwiftUI

/// Everything about one listener: which project, which process, and what to do with it.
struct PortDetailView: View {
    let store: PortsStore
    let portID: ListeningPort.ID
    let onBack: () -> Void

    @State private var confirmingStop = false
    @State private var stopFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Button(action: onBack) {
                Label("Ports", systemImage: "chevron.left")
                    .font(DS.Typography.bodyMedium)
            }
            .buttonStyle(.plain)
            .clickableCursor()
            .foregroundStyle(DS.Palette.accent)
            .keyboardShortcut(.leftArrow, modifiers: .command)

            if let port = store.port(id: portID) {
                header(port)
                info(port)
                actions(port)
            } else {
                EmptyState(symbol: "checkmark.circle", title: "Process ended",
                           message: "Nothing is listening on this port any more.")
            }
        }
    }

    // MARK: - Sections

    private func header(_ port: ListeningPort) -> some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            Text(verbatim: ":\(port.port)")
                .font(DS.Typography.display)
                .foregroundStyle(DS.Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(port.displayName).font(DS.Typography.title).lineLimit(1)
                HStack(spacing: DS.Space.xs) {
                    if let framework = port.project?.framework { StatusBadge(text: framework, tint: DS.Palette.accent) }
                    if port.isExposed {
                        StatusBadge(text: "LAN", tint: DS.Palette.warning)
                    } else {
                        StatusBadge(text: "Local only")
                    }
                }
            }
        }
    }

    private func info(_ port: ListeningPort) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if port.category == .service {
                InfoRow(label: "Address", value: "localhost:\(port.port)")
            } else {
                InfoRow(label: "URL", value: port.url.absoluteString)
            }
            if let project = port.project {
                InfoRow(label: "Project", value: project.subpath.map { "\(project.name) › \($0)" } ?? project.name)
                InfoRow(label: "Folder", value: Launcher.abbreviate(project.packagePath), lineLimit: 2)
                if let branch = project.branch { InfoRow(label: "Branch", value: branch) }
            } else if let dir = port.workingDirectory, dir != "/" {
                InfoRow(label: "Folder", value: Launcher.abbreviate(dir), lineLimit: 2)
            }
            InfoRow(label: "Process", value: "\(port.processName) · PID \(port.pid)")
            if let elapsed = port.elapsed {
                InfoRow(label: "Running", value: RelativeTime.shortDuration(elapsed), copyable: false)
            }
            InfoRow(label: "Usage", value: usage(port), copyable: false)
            InfoRow(label: "Bound to", value: port.addresses.joined(separator: ", ") + (port.isExposed ? " (reachable on LAN)" : ""))
            if let command = port.command {
                InfoRow(label: "Command", value: command, monospaced: true, lineLimit: 3)
            }
        }
    }

    @ViewBuilder private func actions(_ port: ListeningPort) -> some View {
        let folder = port.project?.packagePath ?? port.workingDirectory.flatMap { $0 == "/" ? nil : $0 }

        // Databases and other services don't speak HTTP and have no source to edit.
        let isService = port.category == .service

        HStack(spacing: DS.Space.xs) {
            if !isService {
                ActionButton(title: "Open", symbol: "safari") { Launcher.openURL(port.url) }
            }
            if let folder {
                if !isService {
                    ActionButton(title: Launcher.editorName, symbol: "chevron.left.forwardslash.chevron.right") {
                        Launcher.openInEditor(port.project?.root ?? folder)
                    }
                }
                ActionButton(title: "Terminal", symbol: "terminal") { Launcher.openInTerminal(folder) }
                ActionButton(title: "Finder", symbol: "folder") { Launcher.revealInFinder(folder) }
            }
        }

        if port.isOwnedByCurrentUser {
            stopControl(port)
        }
    }

    /// Two-step stop instead of an alert: alerts would steal focus from the menu-like panel.
    @ViewBuilder private func stopControl(_ port: ListeningPort) -> some View {
        if confirmingStop {
            HStack(spacing: DS.Space.xs) {
                Text("Stop \(port.processName)?")
                    .font(DS.Typography.caption)
                    .lineLimit(1)
                Spacer()
                Button("Cancel") { confirmingStop = false }
                    .controlSize(.small)
                    .clickableCursor()
                Button("Stop", role: .destructive) {
                    Task {
                        stopFailed = !(await store.kill(port))
                        confirmingStop = false
                    }
                }
                .controlSize(.small)
                .clickableCursor()
                .keyboardShortcut(.defaultAction)
                Button("Force") {
                    Task {
                        stopFailed = !(await store.kill(port, force: true))
                        confirmingStop = false
                    }
                }
                .controlSize(.small)
                .clickableCursor()
                .help("Send SIGKILL: stops immediately, without cleanup")
            }
        } else {
            ActionButton(title: stopFailed ? "Couldn't stop, try again" : "Stop process", symbol: "stop.circle", role: .destructive) {
                confirmingStop = true
            }
        }
    }

    private func usage(_ port: ListeningPort) -> String {
        var parts: [String] = []
        if let bytes = port.memoryBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory))
        }
        if let cpu = port.cpuPercent {
            parts.append(String(format: "CPU %.1f%%", cpu))
        }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}
