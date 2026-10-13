import Defaults
import KeyboardShortcuts
import SwiftUI

/// An account that can be shown in the menu bar.
struct MenuBarAccountOption: Identifiable {
    let id: String
    let title: String
    /// Short form for the dropdown's label: "hoang", "Codex".
    let name: String
}

struct SettingsView: View {
    var menuBarAccounts: [MenuBarAccountOption] = []
    /// What the menu bar shows while the user hasn't picked yet.
    var defaultMenuBarAccounts: [String] = []
    /// claude-mem's observer runs on DeepSeek instead of the Codex login.
    var claudeMemOnDeepSeek = false

    @Default(.menuBarStyle) private var menuBarStyle
    @Default(.menuBarAccounts) private var chosenAccounts
    @Default(.aiUsageInterval) private var aiUsageInterval
    @Default(.usageWarnPercent) private var usageWarnPercent
    @Default(.usageNotifications) private var usageNotifications
    @Default(.claudeMemNotifications) private var claudeMemNotifications
    @Default(.claudeMemCodexLimitPercent) private var claudeMemCodexLimitPercent
    @Default(.claudeMemDeepSeekLeftPercent) private var claudeMemDeepSeekLeftPercent

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionHeader(title: "Settings", subtitle: "DevDock \(AppInfo.version)")

            LaunchAtLoginRow()

            SettingRow(title: "Toggle panel") {
                KeyboardShortcuts.Recorder(for: .togglePanel)
            }

            SettingRow(title: "Open projects") {
                KeyboardShortcuts.Recorder(for: .openProjects)
            }

            SettingRow(title: "Update AI usage every") {
                Picker("", selection: $aiUsageInterval) {
                    Text("1m").tag(1)
                    Text("5m").tag(5)
                    Text("15m").tag(15)
                    Text("30m").tag(30)
                }
                .labelsHidden()
                .clickableCursor()
                .fixedSize()
            }

            SettingRow(title: "Menu bar shows") {
                Picker("", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .clickableCursor()
                .fixedSize()
            }

            if menuBarStyle != .icon, !menuBarAccounts.isEmpty {
                SettingRow(title: "Menu bar accounts") {
                    Menu(menuBarSummary) {
                        ForEach(menuBarAccounts) { account in
                            Toggle(account.title, isOn: shownBinding(account.id))
                        }
                    }
                    .menuStyle(.button)
                    .clickableCursor()
                    .fixedSize()
                }
            }

            SettingRow(title: "Warn when quota reaches") {
                Picker("", selection: $usageWarnPercent) {
                    Text("70%").tag(70)
                    Text("80%").tag(80)
                    Text("90%").tag(90)
                }
                .labelsHidden()
                .clickableCursor()
                .fixedSize()
            }

            // Follows the account claude-mem's observer runs on.
            SettingRow(title: "claude-mem limit") {
                Group {
                    if claudeMemOnDeepSeek {
                        Picker("", selection: $claudeMemDeepSeekLeftPercent) {
                            ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)% left").tag($0) }
                            Text("Never").tag(0)
                        }
                        .help("Notify when the balance claude-mem runs on drops under this share of what it was after the last top-up.")
                    } else {
                        Picker("", selection: $claudeMemCodexLimitPercent) {
                            Text("25% used").tag(25)
                            Text("50% used").tag(50)
                            Text("75% used").tag(75)
                            Text("Never").tag(0)
                        }
                        .help("Notify when claude-mem alone has used this share of a quota window of the account it runs on.")
                    }
                }
                .labelsHidden()
                .clickableCursor()
                .fixedSize()
            }

            SettingRow(title: "Notify about AI quota") {
                Toggle("", isOn: $usageNotifications)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .clickableCursor()
                    .onChange(of: usageNotifications) { _, enabled in
                        if enabled { Notifier.requestPermission() }
                    }
            }

            SettingRow(title: "Notify about claude-mem") {
                Toggle("", isOn: $claudeMemNotifications)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .clickableCursor()
                    .onChange(of: claudeMemNotifications) { _, enabled in
                        if enabled { Notifier.requestPermission() }
                    }
            }
            .help("When it stops saving memories, falls behind for 30 minutes while you work, or recovers.")

            Text("Ports update live while the panel is open. Press ↻ to update everything now.")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AuthorLink()
        }
    }

    private var shownAccounts: [String] { chosenAccounts ?? defaultMenuBarAccounts }

    /// "hoang, vu", or a count when the names don't fit.
    private var menuBarSummary: String {
        let names = menuBarAccounts.filter { shownAccounts.contains($0.id) }.map(\.name)
        switch names.count {
        case 0: return "None"
        case 1...2: return names.joined(separator: ", ")
        default: return "\(names.count) accounts"
        }
    }

    private func shownBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { shownAccounts.contains(id) },
            set: { shown in
                var ids = shownAccounts.filter { $0 != id }
                if shown { ids.append(id) }
                chosenAccounts = ids
            }
        )
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            Text(title).font(DS.Typography.body)
            Spacer()
            control
        }
    }
}

/// Reads the real state from macOS each time, since the user can change it in System Settings too.
private struct LaunchAtLoginRow: View {
    @State private var isEnabled = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            SettingRow(title: "Launch at login") {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { enable in
                        LoginItem.setEnabled(enable)
                        isEnabled = LoginItem.isEnabled
                        needsApproval = LoginItem.needsApproval
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .clickableCursor()
            }
            if needsApproval {
                Button("Allow DevDock in System Settings › Login Items") { LoginItem.openSystemSettings() }
                    .buttonStyle(.link)
                    .font(DS.Typography.caption)
                    .clickableCursor()
            } else if !LoginItem.isInstalled {
                Text("Running from a build folder. Run `make install` so login starts the installed copy.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            isEnabled = LoginItem.isEnabled
            needsApproval = LoginItem.needsApproval
        }
    }
}

/// "DevDock 0.1.0 · by npmh0310", linking to the author's GitHub.
private struct AuthorLink: View {
    var body: some View {
        Button {
            Launcher.openURL(AppInfo.authorURL)
        } label: {
            HStack(spacing: DS.Space.xs) {
                Text("DevDock \(AppInfo.version) · by")
                Text(AppInfo.author).fontWeight(.semibold)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .clickableCursor()
        .help(AppInfo.authorURL.absoluteString)
    }
}
